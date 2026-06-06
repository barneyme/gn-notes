# gn
get notes

## Prerequisites:

Before installing gn ensure your Github
                    environment is set up.

You need a GitHub account and a GitHub personal
                                access token. Git is not required.

When creating the token, grant it the repo scope (full control of
                                private repositories). Save the token - you'll
                                need it in the configuration setup step below.

Log into GitHub, click New Repository , and name it gn . Ensure you explicitly change
                                visibility to Private so your
                                data stays hidden. Do not setup with a README,
                                license, or .gitignore layout template.

## Download gn

Enter the information you generated in the steps above to
                    generate an automated installer, or manually configure gn using the directions below.

### Option A: Installer (Recommended)

Fill out your Github information to generate an install.sh script tailored to your
                        environment.

Make Executable

### Option B: Manual Set Up

```
#!/usr/bin/env bash

# --- Configuration ---

NOTES_DIR=
"$HOME/gn"

# --- Load Config ---

CONFIG_FILE=
"$NOTES_DIR/gn.conf"

if
 [ -f 
"$CONFIG_FILE"
 ]; 
then

    . 
"$CONFIG_FILE"

else

    
echo
 
"Error: No config found at $CONFIG_FILE"

    
echo
 
"Create it with:"

    
echo
 
"  GH_TOKEN=yourtoken"

    
echo
 
"  GH_OWNER=yourusername"

    
echo
 
"  GH_REPO=yourrepo"

    
exit
 1

fi

GH_API=
"https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents"

mkdir
 -p 
"$NOTES_DIR"

cd
 
"$NOTES_DIR"
 || { 
echo
 
"Error: Could not access $NOTES_DIR"
; 
exit
 1; }

# --- GitHub API Sync Functions (used when git is not available) ---

pull_from_github() {
    
local
 file=
"$1"

    
local
 response content
    response=$(curl -s -H 
"Authorization: token $GH_TOKEN"
 
"$GH_API/$file"
)
    content=$(echo 
"$response"
 | grep 
'"content"'
 | sed 
's/.*"content": *"\(.*\)".*/\1/'
 | tr -d 
'\\n'
)
    
if
 [ -n 
"$content"
 ]; 
then

        
echo
 
"$content"
 | base64 -d > 
"$file"
 2>/dev/null || 
echo
 
"$content"
 | base64 -D > 
"$file"

    
fi

}

push_to_github() {
    
local
 file=
"$1"

    
local
 sha content msg api_url
    api_url=
"$GH_API/$file"

    sha=$(curl -s -H 
"Authorization: token $GH_TOKEN"
 
"$api_url"
 | grep 
'"sha"'
 | head -1 | sed 
's/.*"sha": *"\([^"]*\)".*/\1/'
)
    content=$(base64 -w0 < 
"$file"
 2>/dev/null || base64 < 
"$file"
)
    msg="Note update: $file on $(date '+%Y-%m-%d %H:%M:%S')"
    
local
 sha_field=
""

    [ -n 
"$sha"
 ] && sha_field=
",\"sha\":\"$sha\""

    curl -s -X PUT -H 
"Authorization: token $GH_TOKEN"
 
"$api_url"
 \
        -d 
"{\"message\":\"$msg\",\"content\":\"$content\"$sha_field}"
 > /dev/null
}

# --- Help Text Function ---

show_help() {
    
echo
 
"Usage: gn [options] [note_name]"

    
echo
 
""

    
echo
 
"Options:"

    
echo
 
"  -h        Show this help message"

    
echo
 
"  -l        List all notes in your notes directory"

    
echo
 
"  -g QUERY  Search for text across all notes (grep)"

    
echo
 
"  -t        Quickly open today's journal note (YYYY-MM-DD.md)"

    
echo
 
""

    
echo
 
"Examples:"

    
echo
 
"  gn                  Opens index.md"

    
echo
 
"  gn daily-log        Opens daily-log.md"

    
echo
 
"  gn work/todo        Opens work/todo.md"

    
echo
 
"  gn -g 'api key'     Searches notes for the term 'api key'"

    
echo
 
"  gn -t               Opens a scratchpad for today's date"

    
exit
 0
}

# --- List Files Function ---

list_notes() {
    
echo
 
"Current Notes in $NOTES_DIR:"

    
if
 [ -d 
"$NOTES_DIR"
 ]; 
then

        find . -type f -not -name 
"gn.conf"
 -not -path '*/.*' | sed 
's|^\./||'
 | sort
    
fi

    
exit
 0
}

# --- Search Inside Notes Function ---

search_notes() {
    
echo
 
"Searching for '$1' inside notes..."

    grep -Rin 
"$1"
 . --exclude-dir=
".git"
 --exclude=
"gn.conf"

    
exit
 0
}

# --- Parse Flags ---

while
 
getopts
 
"hlg:t"
 opt; 
do

    
case
 
${opt}
 
in

        h ) show_help ;;
        l ) list_notes ;;
        g ) search_notes 
"$OPTARG"
 ;;
        t ) NOTE_NAME=$(date 
'+%Y-%m-%d'
) ;;
        \? ) show_help ;;
    esac

done

shift
 
$((OPTIND -1))

# If -t wasn't passed, get note name from command line arguments

if
 [ -z 
"$NOTE_NAME"
 ]; 
then

    NOTE_NAME=
"${1:-index}"

fi

if
 [[ 
"$NOTE_NAME"
 == 
"gn.conf"
 ]]; 
then

    
echo
 
"Error: Protection rule triggered. Cannot edit configuration file via gn script loop."

    
exit
 1

fi

if
 [[ 
"$NOTE_NAME"
 != *.md ]]; 
then

    NOTE_NAME=
"${NOTE_NAME}.md"

fi

NOTE_DIR_PATH=$(
dirname
 
"$NOTE_NAME"
)

if
 [ 
"$NOTE_DIR_PATH"
 != 
"."
 ]; 
then

    
mkdir
 -p 
"$NOTE_DIR_PATH"

fi

# --- Sync From Cloud ---

echo
 
"Fetching latest cloud updates..."

pull_from_github 
"$NOTE_NAME"

# --- Open the Editor ---

${EDITOR:-nano}
 
"$NOTE_NAME"

# --- Sync Back to GitHub ---

echo
 
"Syncing changes to GitHub..."

push_to_github 
"$NOTE_NAME"

echo
 
"Sync complete!"
```

## Manual Installation

If you prefer not to use the automated install.sh script, follow these steps to
                    configure gn manually:

The config file lives inside your notes
                                directory as a .conf file. Create the directory
                                first, then the config:

```
mkdir -p ~/gn
nano ~/gn/gn.conf
```

Add these three lines, substituting your
                                credentials gathered from the infrastructure
                                section:

```
GH_TOKEN=ghp_yourpersonalaccesstoken
GH_OWNER=GITHUB-USERNAME
GH_REPO=gn
```

Make the downloaded gn.sh script
                                executable and copy it into your /usr/local/bin ) so it's accessible
                                anywhere:

```
chmod +x gn.sh
sudo cp gn.sh /usr/local/bin/gn
```

Run gn from your Terminal. Use flags for advanced
                            features.

```
gn                  # Opens your main index.md
gn daily-log        # Creates/Opens daily-log.md
gn work/reminders   # Creates work/ directory and opens reminders.md
gn -h               # Displays help page
gn -l               # Lists all your notes (excludes configuration configuration metrics)
gn -g "todo"        # Finds text matching "todo" inside any note
gn -t               # Opens today's automated scratchpad entry
```

## Setting Up a Second Computer

Your notes live in GitHub and sync via the API, so there's
                    nothing to clone. Just create the directory, drop in your
                    config file, and install the script.

```
mkdir -p ~/gn
nano ~/gn/gn.conf
```

```
GH_TOKEN=ghp_yourpersonalaccesstoken
GH_OWNER=GITHUB-USERNAME
GH_REPO=gn
```

Download gn.sh using the button
                                above and install it:

```
chmod +x gn.sh
sudo cp gn.sh /usr/local/bin/gn
```

That's it - run gn and it will pull
                                your notes before opening the editor, just like
                                on your first machine.

## Editing Notes in the Browser

If you're on a machine without a terminal - or just want a
                    quick edit from any browser - you can use github.dev , a full VS Code instance that
                    runs entirely in the browser and commits directly to your
                    repo.

Navigate to your gn repo on GitHub,
                                then press . (period) on your
                                keyboard. The page reloads as a VS Code editor
                                with all your notes in the file tree on the
                                left.

Or just swap github.com for github.dev in the URL directly:

```
https://github.dev/YOUR-USERNAME/gn
```

Open any .md file and make your
                                edits. When done, open the Source Control panel
                                ( Ctrl+Shift+G / Cmd+Shift+G ), enter a commit
                                message, and click the checkmark. The change is
                                pushed to your repo immediately.

The next time you run gn on any
                                note, it pulls the latest version from GitHub
                                before opening the editor - no manual sync
                                needed.

Note: gn syncs
                                per-file, so if you edit the same note in
                                github.dev and in the terminal at the same time,
                                the last push wins. Avoid editing the same note
                                simultaneously from two places.
