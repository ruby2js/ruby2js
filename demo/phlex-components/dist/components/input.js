export class Input extends Phlex.HTML {
  render({ attrs, disabled, placeholder, required, type }) {
    let _phlex_out = "";
    let classes = ["input"];
    if (disabled) classes.push("input-disabled");
    _phlex_out += `<input type="${type}" class="${classes.join(" ")}" placeholder="${placeholder}" disabled="${disabled}" required="${required}">`;
    return _phlex_out
  }
}