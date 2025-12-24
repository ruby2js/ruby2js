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
    )))}</div></section><section class="component-section"><h2 class="section-title">Input</h2><div class="form-row">${_phlex_out += Input.render({placeholder: "Enter text..."})}${_phlex_out += Input.render({type: "email", placeholder: "Email address"})}${_phlex_out += Input.render({disabled: true, placeholder: "Disabled input"})}</div></section><section class="component-section"><h2 class="section-title">Badges</h2><div class="button-row">${this.render(new Badge(() => (
      "Default"
    )))}${this.render(new Badge({variant: "secondary"}, () => "Secondary"))}${this.render(new Badge({variant: "destructive"}, () => (
      "Destructive"
    )))}${this.render(new Badge({variant: "outline"}, () => "Outline"))}</div></section><section class="component-section"><h2 class="section-title">Alerts</h2><div class="alert-stack">${this.render(new Alert({title: "Heads up!"}, () => (
      "This is a default alert message."
    )))}${this.render(new Alert({variant: "success", title: "Success"}, () => (
      "Your changes have been saved."
    )))}${this.render(new Alert({variant: "warning", title: "Warning"}, () => (
      "Please review before continuing."
    )))}${this.render(new Alert({variant: "destructive", title: "Error"}, () => (
      "Something went wrong."
    )))}</div></section><section class="component-section"><h2 class="section-title">Cards</h2><div class="card-grid">${_phlex_out += Card.render({}, () => (_phlex_out += CardHeader.render({}, () => (this.render(new CardTitle(() => (
      "Card Title"
    ))), this.render(new CardDescription(() => "Card description goes here.")))), _phlex_out += CardContent.render({}, () => "<p>This is the main content area of the card.</p>"), _phlex_out += CardFooter.render({}, () => this.render(new Button(() => (
      "Action"
    ))))))}${_phlex_out += Card.render({}, () => (_phlex_out += CardHeader.render({}, () => (this.render(new CardTitle({as: "h4"}, () => (
      "Secondary Card"
    ))), this.render(new CardDescription(() => "Using h4 for the title.")))), _phlex_out += CardContent.render({}, () => "<p>Cards can contain any nested content.</p>"), _phlex_out += CardFooter.render({}, () => (this.render(new Button({variant: "outline"}, () => (
      "Cancel"
    ))), this.render(new Button(() => "Confirm"))))))}</div></section><section class="component-section"><h2 class="section-title">Dialog</h2>${_phlex_out += Dialog.render({title: "Are you sure?", description: "This action cannot be undone."}, () => ("<p>This will permanently delete your account and all associated data.</p>", `<div class="dialog-actions">${this.render(new Button({
      variant: "outline",
      data_action: "click->dialog#close"
    }, () => "Cancel"))}${this.render(new Button({variant: "destructive"}, () => (
      "Delete Account"
    )))}</div>`))}</section><section class="component-section"><h2 class="section-title">Tabs</h2>${_phlex_out += Tabs.render({tabs: [
      {label: "Account", content: "Make changes to your account here."},
      {label: "Password", content: "Change your password here."},
      {label: "Settings", content: "Manage your settings here."}
    ]})}</section></div>`;

    return _phlex_out
  }
}