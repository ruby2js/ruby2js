// ERB to Ruby compiler for Ruby2JS-on-Rails
// This produces Ruby code that can be transpiled to JavaScript.
// Both Ruby and selfhost builds use this same compiler for consistency.
export class ErbCompiler {
  #template;

  constructor(template) {
    this.#template = template
  };

  // Compile ERB template to Ruby code
  // Format: _buf = ::String.new; _buf << 'literal'.freeze; _buf << ( expr ).to_s; ... _buf.to_s
  // Key: buffer operations use semicolons, code blocks use newlines
  get src() {
    let ruby_code = "_buf = ::String.new;";
    let pos = 0;

    while (pos < this.#template.length) {
      let text;
      let erb_start = this.#template.indexOf("<%", pos);

      // Ruby's index returns nil, JS's indexOf returns -1
      if (erb_start == null || erb_start < 0) {
        // No more ERB tags, add remaining text
        text = this.#template.slice(pos);

        if (text && text.length != 0) {
          ruby_code += ` _buf << ${this.#emit_ruby_string(text)};`
        };

        break
      };

      // Find end of ERB tag first to check if this is a code block
      let erb_end = this.#template.indexOf("%>", erb_start);

      // Ruby's index returns nil, JS's indexOf returns -1
      if (erb_end == null || erb_end < 0) throw "Unclosed ERB tag";
      let tag = this.#template.slice(erb_start + 2, erb_end);
      let is_code_block = !tag.trim().startsWith("=") && !tag.trim().startsWith("-");

      // Add text before ERB tag
      if (erb_start > pos) {
        text = this.#template.slice(pos, erb_start);

        // For code blocks, strip trailing whitespace on the same line as <% %>
        // This matches Ruby Erubi behavior where leading indent before <% %> is not included
        if (is_code_block) {
          if (text.includes("\n")) {
            let last_newline = text.lastIndexOf("\n") // Ruby: rindex, JS: lastIndexOf;
            let after_newline = text.slice(last_newline + 1) ?? "";
            if (/^\s*$/m.test(after_newline)) text = text.slice(0, last_newline + 1)
          }
        };

        if (text && text.length != 0) {
          ruby_code += ` _buf << ${this.#emit_ruby_string(text)};`
        }
      };

      // Handle -%> (trim trailing newline)
      let trim_trailing = tag.endsWith("-");
      if (trim_trailing) tag = tag.slice(0, -1);
      tag = tag.trim();
      let is_output_expr = false;

      if (tag.startsWith("=")) {
        // Output expression: <%= expr %>
        let expr = tag.slice(1).trim();

        // Check if this is a block expression (ends with 'do')
        if (expr.endsWith(" do") || expr.endsWith("\tdo")) {
          // Block expression: use .append= pattern that ERB filter expects
          ruby_code += ` _buf.append= ${expr}\n`
        } else {
          ruby_code += ` _buf << ( ${expr} ).to_s;`;
          is_output_expr = true
        }
      } else if (tag.startsWith("-")) {
        // Unescaped output: <%- expr %> (same as <%= for our purposes)
        let expr = tag.slice(1).trim();
        ruby_code += ` _buf << ( ${expr} ).to_s;`;
        is_output_expr = true
      } else {
        // Code block: <% code %> - use newline, not semicolon
        ruby_code += ` ${tag}\n`
      };

      pos = erb_end + 2;

      // Trim trailing newline after code blocks (like Erubi does by default)
      if ((trim_trailing || is_code_block) && pos < this.#template.length && this.#template[pos] == "\n") {
        pos++
      };

      // For output expressions, if followed by a newline, add it as a separate literal
      // This matches Ruby Erubi which splits the newline after output expressions
      if (is_output_expr && pos < this.#template.length && this.#template[pos] == "\n") {
        ruby_code += ` _buf << ${this.#emit_ruby_string("\n")};`;
        pos++
      }
    };

    ruby_code += "\n_buf.to_s";
    return ruby_code
  };

  // Emit a Ruby string literal using double quotes
  // Escape \, ", and newlines to keep strings on single lines
  #emit_ruby_string(str) {
    let escaped = str.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"").replaceAll(
      "\n",
      "\\n"
    );

    return `"${escaped}"`
  }
}
