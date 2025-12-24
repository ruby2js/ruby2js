export class Button extends Phlex.HTML {
  static VARIANTS = {
    primary: "btn-primary",
    secondary: "btn-secondary",
    destructive: "btn-destructive",
    outline: "btn-outline",
    ghost: "btn-ghost"
  };

  static SIZES = {sm: "btn-sm", md: "btn-md", lg: "btn-lg"};

  render({ attrs, disabled, size, type, variant }) {
    let _phlex_out = "";
    let classes = ["btn", Button.VARIANTS[variant], Button.SIZES[size]];
    if (disabled) classes.push("btn-disabled");
    _phlex_out += `<button type="${type}" class="${classes.join(" ")}" disabled="${disabled}"></button>`;
    return _phlex_out
  }
}