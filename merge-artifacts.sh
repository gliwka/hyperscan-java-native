#!/usr/bin/bash
set -euox pipefail

# Make sure all artifacts have the same timestamp overwriting duplicates
timestamp=$(date +"%Y%m%d.%H%M%S")
find target/staging-deploy -type f | while read file; do
    newfile=$(echo "$file" | sed -E "s/[0-9]{8}\.[0-9]{6}/$timestamp/g")
    if [ "$file" != "$newfile" ]; then
        mv "$file" "$newfile"
    fi
done

# Delete hashsums, they will be recreated
find target/staging-deploy -type f \( -name "*.md5" -o -name "*.sha1" \) -delete