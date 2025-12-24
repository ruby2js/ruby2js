export class Badge extends Phlex.HTML {
  static VARIANTS = {
    default: "badge-default",
    secondary: "badge-secondary",
    destructive: "badge-destructive",
    outline: "badge-outline"
  };

  render({ attrs, variant }) {
    let _phlex_out = "";
    _phlex_out += `<span class="${`badge ${Badge.VARIANTS[variant]}`}"></span>`;
    return _phlex_out
  }
}