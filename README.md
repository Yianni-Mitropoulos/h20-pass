# Hero To Zero Pass

## Purpose

Minimal and auditable deterministic password generator for Linux, written entirely in Bash. Designed for use with QubesOS.

## Features

- Minimal attack surface  
- No internet or network involvement  
- Base26 and Base64 outputs supported
- Feels responsive (password password computed while you enter the service name)
- Avoids insecure fallbacks
- Decently strong Argon2id parameters, tuned to work comfortably on mobile
- Uses large hashes (2048 bits) to help protect against cold-boot vulnerabilities
- No unnecessary cryptographic primitives (no SHA2/SHA3) and no "security theatre"  

## This tool does NOT:

- Store your service names  
- Track or log what you do  
- Require internet access  
- Require updates

## Requirements

- Linux only  
- Scripts provided for Debian and Fedora  
- Use an LLM if you need to port to other platforms

## Security Note

Nothing is ever written to disk; the tool stores only a **session-bound pepper** in RAM.

However, if an attacker can compromise a program running in the same VM, they can:  
- Read the pepper from RAM, and
- Log your keystrokes, and
- Read the clipboard (generated passwords are copied there)

To mitigate these risks, follow these best practices:
- Run in a **dedicated disposable VM**  
- Ensure this VM has **strictly no internet access**  
- Do not paste anything into this VM, ever  
- Do not update this VM without good reason  
- Never type your **master passphrase** or **password** into another VM or untrusted device

## Installation

Copy and paste the appropriate version of the script into your terminal, then restart the terminal or run `source ~/.bashrc` (or `source /etc/bash.bashrc` for all users). If you're unsure which version to use for your system, ask AI.

NOTE: This installs the functions for **all users**.

## Uninstallation

To uninstall, edit the file you appended the functions to and remove them:  
- **Fedora**: `/etc/bashrc`  
- **Debian**: `/etc/bash.bashrc`

## Overview

Given:  
- **Passphrase** (entered once per session; stored temporarily in keyring)  
- **Master password** (entered every time)  
- **Service name** (entered every time)

It deterministically:  
- Produces a 16-character password for that service  
- Copies the password to the system clipboard for pasting  

If you want to track services or service names, you have to do that yourself, preferably in a different VM altogether.

## Usage

After installing, close and reopen your shell, or run the `source` command (e.g., `source ~/.bashrc` or `source /etc/bash.bashrc` for all users).

Provides three commands:  
- `h20-login`  (Use this at the start of each session.)  
- `h20-pass`   (Produces a service password from a master password and service name.)  
- `h20-logout` (Clears your passphrase hash from the session keyring.)

## Base26 vs Base64

By default, `h20-pass` uses **Base26**. This ensures that it's easy to type your service passwords into your smartphone.  

If a website requires special characters, you may prefer to use **Base64** mode. To do this, prepend a full stop (`.`) to the service name. This also has the effect of appending a full stop (`.`) to the derived password, to ensure you have at least one special character.

**Example:**

**Master password**: `foobar`  
**Service name**: `amazon`  
Copies `bpeyfpntusrvajlg` to clipboard.

**Master password**: `foobar`  
**Service name**: `.amazon`  
Copies `.Xpqd3iPtejUC0r3` to clipboard.

## General Advice

Keep everything (passphrase, password, service names) **lowercase**, unless you have a good reason to do otherwise. This ensures that you can also use `h20-pass` on your phone, if you're forced to (Termux, etc.).

## Passphrase Advice

You only have to type your **passphrase** once per session, so it might as well be long.

If you're not obsessive about security, you can just use your full name:

    yiannimitropoulos

This salts the rest of what you do, helping to protect against precomputation attacks.

If you want an extra level of protection, keep your **passphrase secret**, and use it as a pepper. I recommend using **pen and paper** to come up with a limerick or short poem, like so:

    haileyhigginshandedfood  
    tosillymillyjacksonrude

Destroy the paper only once you can easily remember the passphrase.

Also, be sure to **log in with your passphrase BEFORE starting any qubes with access to your camera**. That way, even if someone is able to film your hands while you're typing your password, they still won't have your passphrase, and thus cannot recover any of your service passwords.

## Master Password Advice

As you must type your **master password** every single time you want to generate a service password, **maximizing entropy-per-keystroke** is essential. I recommend using 16 random lowercase characters. This ensures that you can easily type your master password into a phone if needed.

To generate these characters:  
1. Roll two dice, call them X and Y, for each character.  
2. Compute `6X + Y`.  
3. Use the following lookup table to get the character, and roll again (R/A) if the aforementioned value exceeds 25.

| Value | Char |
|-------|------|
| 7     | h    |
| 8     | i    |
| 9     | j    |
| 10    | k    |
| 11    | l    |
| 12    | m    |
| 13    | n    |
| 14    | o    |
| 15    | p    |
| 16    | q    |
| 17    | r    |
| 18    | s    |
| 19    | t    |
| 20    | u    |
| 21    | v    |
| 22    | w    |
| 23    | x    |
| 24    | y    |
| 25    | z    |
| 26    | a    |
| 27    | b    |
| 28    | c    |
| 29    | d    |
| 30    | e    |
| 31    | f    |
| 32    | g    |
| 33    | R/A  |
| 34    | R/A  |
| 35    | R/A  |
| 36    | R/A  |
| 37    | R/A  |
| 38    | R/A  |
| 39    | R/A  |
| 40    | R/A  |
| 41    | R/A  |
| 42    | R/A  |

## Attacks and Mitigations

- **Brute force without quantum assistance** (not feasible, too many combinatorial possibilities)  
- **Brute force with quantum assistance** (not feasible, as Argon2id uses a lot of memory, and quantum memory is fragile and expensive)  
- **Supply chain attacks** (mitigation: `h20-pass` never needs updating)  
- **WiFi keyboard compromise** (mitigation: use reputable WiFi keyboards, or avoid them altogether)  
- **QubesOS sys-usb compromise** (mitigation: use a non-USB keyboard, e.g., PS/2)  
- **Filming you with your own webcam** (mitigation: do NOT open any qubes with camera access until after you've logged in with your passphrase)  
- **Someone sits down at your unlocked computer and gets the hash of your passphrase** (mitigation: use a strong password, keep your computer locked)  
- **Cold boot attacks** (mitigation: use a terminal/memory allocator that reliably clears memory after use)  
- **Xen/QubesOS dom0 compromise** (mitigation: run for the hills!)