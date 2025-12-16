#!/bin/bash
#
# Build script for Ruby2JS WASM demo
#
# This script downloads a pre-built Ruby 4.0 WASM from npm and packs
# the ruby2js gem and its dependencies on top.
#
# Requirements:
#   - npm (for downloading pre-built Ruby WASM)
#   - rbwasm gem (gem install ruby_wasm)
#
# Usage:
#   ./build.sh                    # Build with default settings
#   ./build.sh --output file.wasm # Specify output filename
#
# Note: Ruby 4.0 preview is required because Ruby 3.3/3.4 have issues
# with the WASI VFS that prevent require from working correctly.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build-tmp"

# Use Ruby 4.0 preview - this is required for Prism parser support
# and working require in WASI environment
# Note: Using dated preview version that includes Ruby 4.0 with Prism
NPM_PACKAGE="@ruby/wasm-wasi@2.7.2-2025-11-28-a"
OUTPUT_FILE="ruby2js.wasm"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--output filename.wasm]"
      exit 1
      ;;
  esac
done

echo "=== Ruby2JS WASM Build ==="
echo "Ruby: 4.0 (head)"
echo "Output: $OUTPUT_FILE"
echo ""

# Check for rbwasm
if ! command -v rbwasm &> /dev/null; then
  echo "Error: rbwasm not found. Install with: gem install ruby_wasm"
  exit 1
fi

# Create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Step 1: Download pre-built Ruby WASM from npm
echo "Step 1: Downloading pre-built Ruby WASM..."
npm pack "$NPM_PACKAGE@latest" --silent
tar -xzf *.tgz

# Find the WASM file (location varies by package)
WASM_FILE=$(find package -name "*.wasm" -type f | head -1)
if [[ -z "$WASM_FILE" ]]; then
  echo "Error: No WASM file found in npm package"
  exit 1
fi
echo "  Found: $WASM_FILE"
cp "$WASM_FILE" ruby-base.wasm

# Step 2: Find gem paths
echo ""
echo "Step 2: Locating gem dependencies..."

# Get gem paths using Ruby
AST_PATH=$(ruby -e "puts Gem::Specification.find_by_name('ast').gem_dir + '/lib'")
RACC_PATH=$(ruby -e "puts Gem::Specification.find_by_name('racc').gem_dir + '/lib'")
PARSER_PATH=$(ruby -e "puts Gem::Specification.find_by_name('parser').gem_dir + '/lib'")
RUBY2JS_PATH="$ROOT_DIR/lib"

echo "  ast: $AST_PATH"
echo "  racc: $RACC_PATH"
echo "  parser: $PARSER_PATH"
echo "  ruby2js: $RUBY2JS_PATH"

# Step 3: Pack gems onto WASM
echo ""
echo "Step 3: Packing gems..."

rbwasm pack ruby-base.wasm \
  --dir "$AST_PATH::/gems/ast/lib" \
  --dir "$RACC_PATH::/gems/racc/lib" \
  --dir "$PARSER_PATH::/gems/parser/lib" \
  --dir "$RUBY2JS_PATH::/gems/ruby2js" \
  -o "$SCRIPT_DIR/$OUTPUT_FILE"

# Cleanup
cd "$SCRIPT_DIR"
rm -rf "$BUILD_DIR"

# Report results
WASM_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
echo ""
echo "=== Build Complete ==="
echo "Output: $OUTPUT_FILE ($WASM_SIZE)"
echo ""
echo "Test with:"
echo "  node poc-packed-final.cjs ./$OUTPUT_FILE"
