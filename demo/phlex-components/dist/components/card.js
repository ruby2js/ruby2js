export class Card extends Phlex.HTML {
  render({ attrs }) {
    let _phlex_out = "";
    _phlex_out += "<div class=\"card\"></div>";
    return _phlex_out
  }
};

export class CardHeader extends Phlex.HTML {
  render({ attrs }) {
    let _phlex_out = "";
    _phlex_out += "<div class=\"card-header\"></div>";
    return _phlex_out
  }
};

export class CardTitle extends Phlex.HTML {
  render({ attrs, tag }) {
    let _phlex_out = "";
    [tag]({class: "card-title", ...attrs}, block);
    return _phlex_out
  }
};

export class CardDescription extends Phlex.HTML {
  render({ attrs }) {
    let _phlex_out = "";
    _phlex_out += "<p class=\"card-description\"></p>";
    return _phlex_out
  }
};

export class CardContent extends Phlex.HTML {
  render({ attrs }) {
    let _phlex_out = "";
    _phlex_out += "<div class=\"card-content\"></div>";
    return _phlex_out
  }
};

export class CardFooter extends Phlex.HTML {
  render({ attrs }) {
    let _phlex_out = "";
    _phlex_out += "<div class=\"card-footer\"></div>";
    return _phlex_out
  }
}