export class ShowcaseView extends Phlex.HTML {
  render() {
    let _phlex_out = "";

    _phlex_out += `<div class="container"><h1 class="page-title">Component Library</h1><section class="component-section"><h2 class="section-title">Button Variants</h2><div class="button-row">${this.render(new Button({variant: "primary"}, () => (
      "Primary"
    )))}${this.render(new Button({variant: "secondary"}, () => "Secondary"))}${this.render(new Button({variant: "destructive"}, () => (
      "Destructive"
    )))}${this.render(new Button({variant: "outline"}, () => "Outline"))}${this.render(new Button({variant: "ghost"}, () => (
      "Ghost"
    )))}</div></section><section class="component-section"><h2 class="section-title">Button Sizes</h2><div class="button-row">${this.render(new Button({size: "sm"}, () => (
      "Small"
    )))}${this.render(new Button({size: "md"}, () => "Medium"))}${this.render(new Button({size: "lg"}, () => (
      "Large"
    )))}</div></section><section class="component-section"><h2 class="section-title">Disabled State</h2><div class="button-row">${this.render(new Button({disabled: true}, () => (
      "Disabled"
    )))}${this.render(new Button({variant: "outline", disabled: true}, () => (
      "Disabled Outline"
    )))}</div></section><section class="component-section"><h2 class="section-title">Cards</h2><div class="card-grid">${_phlex_out += Card.render({}, () => (_phlex_out += CardHeader.render({}, () => (this.render(new CardTitle(() => (
      "Card Title"
    ))), this.render(new CardDescription(() => "Card description goes here.")))), _phlex_out += CardContent.render({}, () => "<p>This is the main content area of the card. You can put any content here.</p>"), _phlex_out += CardFooter.render({}, () => this.render(new Button(() => (
      "Action"
    ))))))}${_phlex_out += Card.render({}, () => (_phlex_out += CardHeader.render({}, () => (this.render(new CardTitle({as: "h4"}, () => (
      "Secondary Card"
    ))), this.render(new CardDescription(() => "Using h4 for the title.")))), _phlex_out += CardContent.render({}, () => ("<p>Cards can contain any nested content.</p>", "<ul><li>Item one</li><li>Item two</li><li>Item three</li></ul>")), _phlex_out += CardFooter.render({}, () => (this.render(new Button({variant: "outline"}, () => (
      "Cancel"
    ))), this.render(new Button(() => "Confirm"))))))}</div></section></div>`;

    return _phlex_out
  }
}