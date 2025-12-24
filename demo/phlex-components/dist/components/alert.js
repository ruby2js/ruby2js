export class Alert extends Phlex.HTML {
  static VARIANTS = {
    default: "alert-default",
    destructive: "alert-destructive",
    success: "alert-success",
    warning: "alert-warning"
  };

  render({ attrs, dismissible, title, variant }) {
    let _phlex_out = "";
    _phlex_out += `<div class="${`alert ${Alert.VARIANTS[variant]}`}" role="alert">${title ? _phlex_out += `<div class="alert-title">${String(title)}</div>` : null}<div class="alert-description"></div>${dismissible ? _phlex_out += "<button class=\"alert-dismiss\" type=\"button\" aria-label=\"Dismiss\">×</button>" : null}</div>`;
    return _phlex_out
  }
}