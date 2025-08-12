#!/usr/bin/env bash
#
# =============================================================================
# WARNING: For simplicity, this script is not idempotent. This means that
# running it repeatedly will append these functions repeatedly. Extra copies
# should not cause any issues for your computer. Nevertheless, they can be
# cleared up by navigating to /etc/bash.bashrc and manually deleting the
# repeated definitions.
# =============================================================================
#
# MIT License
# 
# Copyright (c) 2025 Yianni-Mitropoulos
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Update package list (retry until success)
until sudo dnf -y makecache; do sleep 1; done

# Install dependencies (retry until success)
until sudo dnf -y install argon2; do sleep 1; done
until sudo dnf -y install xclip; do sleep 1; done
until sudo dnf -y install keyutils; do sleep 1; done

# Append all functions to /etc/bashrc (retry until success)
# Change this to ~/.bashrc if you want it for just one user.
until sudo tee -a /etc/bashrc > /dev/null <<'EOF'
# base26_reduce
# -------------
# Accepts a string.
# Maps each byte to 'a'..'z' via (ord % 26) + 97
# Does not handle carries or overflows. This is a bytewise utility
# base26_reduce STRING
# same-length mapping: each input byte -> 'a'..'z' via (ord % 26) + 97
base26_reduce() {
    local s=$1
    LC_ALL=C  # byte-wise

    # 1) Get decimal byte values for the string (no printf here)
    local bytes
    bytes=$(echo -n "$s" | od -An -t u1 | tr -s ' \n' ' ')

    # 2) Map each byte -> (b % 26) + 97 and collect numbers
    local vals=() b
    for b in $bytes; do
        vals+=( $(( (b % 26) + 97 )) )
    done

    # 3) Single printf: build \xHH escape sequence string for all bytes at once
    local esc
    esc=$(printf '\\x%02x' "${vals[@]}")

    # 4) Echo the bytes (interpret escapes) and add a newline
    echo -ne "$esc"
    echo
}

# h20-login
# ---------
# Session key setup for h20-pass
# - Derives an Argon2id encoded master string from a passphrase and fixed salt
# - Stores/updates it as a 'user' key in the session keyring (@s) named "h20/passphrase"
# - Prints a 4-character confirmation tag from the encoded hash tail for verification
# - Uses only Argon2id with hard-coded parameters (no env vars)
h20-login() (
    keyname="h20/passphrase"

    # Disable job control to avoid interference in subshells
    set +m

    # Save current terminal settings; always restore on exit
    orig_stty=$(stty -g)
    trap 'stty "$orig_stty"' EXIT

    # Prompt for passphrase (hidden)
    stty -echo
    read -r -p "Passphrase: " pass
    stty echo
    echo

    if [ -z "$pass" ]; then
        echo "ERROR: empty passphrase"
        return 1
    fi

    # Derive Argon2id encoded string
    encoded=$(
        echo -n "$pass" |
            argon2 "h20-login" -id -t 1 -m 21 -p 2 -l 32 2>/dev/null |
            awk '/^Encoded:/ {print $2}'
    )
    if [ -z "$encoded" ]; then
        echo "ERROR: hashing failed"
        return 1
    fi

    # Unset passphrase (this may or may not wipe the data)
    unset pass

    # Confirmation tag: first 4 chars of final Base64 chunk (hashB64)
    tail_b64=$(echo "$encoded" | awk -F'$' '{print $NF}')
    confirm=${tail_b64:0:4}
    echo "Confirm tag: $confirm"

    # Store into the session keyring (@s) as a 'user' key
    if key_id=$(keyctl search @s user "$keyname" 2>/dev/null); then
        if keyctl update "$key_id" "$encoded" >/dev/null 2>&1; then
            echo "Updated session keyring entry '$keyname' (key id: $key_id)."
        else
            echo "ERROR: failed to update existing key '$keyname' (id: $key_id)."
            unset encoded tail_b64 confirm key_id
            return 1
        fi
    else
        if key_id=$(keyctl add user "$keyname" "$encoded" @s 2>/dev/null); then
            echo "Stored in session keyring as '$keyname'."
        else
            echo "ERROR: failed to store in session keyring. Is keyutils available?"
            unset encoded tail_b64 confirm key_id
            return 1
        fi
    fi

    # Unset sensitive vars (this may or may not wipe the data)
    unset encoded tail_b64 confirm key_id keyname
)

# h20-logout
# ----------
# Session key cleanup for h20-pass
# - Looks up the 'user' key "h20/passphrase" in the session keyring (@s)
# - Unlinks it from the session keyring and invalidates it
# - Prints a short status message either way
h20-logout() (
    keyname="h20/passphrase"

    if key_id=$(keyctl search @s user "$keyname" 2>/dev/null); then
        # Unlink from the session keyring and invalidate to be safe
        keyctl unlink "$key_id" @s >/dev/null 2>&1 || true
        keyctl invalidate "$key_id" >/dev/null 2>&1 || true
        echo "Cleared session key '$keyname'."
    else
        echo "No session key named '$keyname' found."
    fi

    unset keyname key_id
)

# h20-pass
# -----------
# A deterministic password generator
# - Formula is: first 16 Base64 chars of fast_hash(service_name, slow_hash(password)).
# - If the service name starts with a full stop (.), use Base64 and append a full stop followed by 15 characters.
# - Otherwise, use Base26 to generate the password.
# - Slow hash is computed while you type your service name.
# - First 4 Base64 chars of the slow hash are printed to the terminal for confirmation.
# - Uses Argon2id only (no SHA2/SHA3, no extra attack surface).
# - Salt for the slow hash is read from the session keyring entry: user "h20/passphrase".
h20-pass() (
    # Disable job control to avoid interference in subshells
    set +m

    # Save current terminal settings so they can be restored later
    orig_stty=$(stty -g)

    # Ensure terminal settings are restored on exit, even if interrupted
    trap 'stty "$orig_stty"' EXIT

    # Fetch salt from session keyring (@s)
    if key_id=$(keyctl search @s user "h20/passphrase" 2>/dev/null); then
        slow_salt=$(keyctl read "$key_id" 2>/dev/null)
    else
        echo "ERROR: No session key 'h20/passphrase' found in the session keyring."
        echo "Hint: run 'h20-login' first to create it, then try again."
        exit 1
    fi
    if [ -z "$slow_salt" ]; then
        echo "ERROR: Failed to read salt from session key 'h20/passphrase'."
        exit 1
    fi

    # Get master password (hidden)
    stty -echo
    read -r -p "Master password: " master
    stty echo
    echo

    # Start master hash as a coprocess (salt comes from keyring)
    coproc {
        echo -n "$master" |
            argon2 "$slow_salt" -id -t 1 -m 21 -p 2 -l 32 2>/dev/null |
            grep '^Encoded:' | awk '{print $2}'
        unset slow_salt
    }

    # Ask for service name
    read -r -p "Service name: " service

    # Get master hash
    read -r password_hash <&"${COPROC[0]}"
    [ -z "$password_hash" ] && { echo "ERROR: master hash failed"; exit 1; }

    # Site-specific hash (Base64 payload)
    site_b64=$(
        echo -n "$service" |
            argon2 "$password_hash" -id -t 1 -m 10 -p 1 -l 24 2>/dev/null |
            grep '^Encoded:' | awk '{print $2}' | awk -F'$' '{print $NF}'
    )

    # Determine password format based on the first character of the service name
    if [[ "${service:0:1}" == "." ]]; then
        # Use Base64 (append full stop and 15 chars)
        pass16=${site_b64:0:15}
        pass16=".$pass16"
        mode="base64"
    else
        # Use Base26 (no modification needed)
        pass16=${site_b64:0:16}
        pass16=$(base26_reduce "$pass16")
        mode="base26"
    fi

    # Copy to clipboard (two loops to give time for pasting)
    echo -n "$pass16" | xclip -selection clipboard -loops 2

    # Print confirmation tag from slow hash
    tag_b64=$(echo "$password_hash" | awk -F'$' '{print $NF}')
    confirm=${tag_b64:0:4}
    echo "Password copied to clipboard ($mode)."
    echo "Confirm tag: $confirm"

    # Unset variables (this may or may not wipe the data)
    unset master password_hash site_b64 pass16 tag_b64 confirm service key_id mode
)
EOF
do sleep 1; done

echo "Installed. Open a new shell and run: h20-login"