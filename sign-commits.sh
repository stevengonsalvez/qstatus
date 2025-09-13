#!/bin/bash
# ABOUTME: Script to rewrite Git history and sign all commits

set -e

echo "Signing all commits in history..."
echo "================================"
echo ""
echo "⚠️  WARNING: This will rewrite history and require force push!"
echo "Current branch will be backed up as 'backup-unsigned'"
echo ""
echo "Press Enter to continue or Ctrl+C to cancel..."
read

# Create backup
git branch -f backup-unsigned

# Get the root commit
ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD)

# Sign all commits from root
git filter-branch -f --commit-filter '
    git commit-tree -S "$@"
' -- --all

echo ""
echo "✅ All commits have been signed!"
echo ""
echo "To push to GitHub (this will rewrite history):"
echo "  git push --force-with-lease origin master"
echo ""
echo "To restore original history:"
echo "  git reset --hard backup-unsigned"