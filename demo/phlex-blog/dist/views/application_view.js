export class ApplicationView extends Phlex.HTML {
  // Override in subclasses
  get title() {
    return "Blog"
  };

  // Helper: truncate text
  truncate(text, { length=100 } = {}) {
    if (!text) return "";

    if (text.length > length) {
      `${text.slice(0, length)}...`
    } else {
      text
    }
  };

  // Helper: format time ago
  time_ago(time) {
    if (!time) return "unknown";
    let seconds = (Date.now - time) / 1_000;

    if (seconds < 60) {
      `${parseInt(seconds)}s ago`
    } else if (seconds < 3_600) {
      `${parseInt(seconds / 60)}m ago`
    } else if (seconds < 86_400) {
      `${parseInt(seconds / 3_600)}h ago`
    } else {
      `${parseInt(seconds / 86_400)}d ago`
    }
  };

  // Helper: format date
  format_date(time) {
    if (!time) return "";
    let date = new Date(time);

    date.toLocaleDateString(
      "en-US",
      {year: "numeric", month: "long", day: "numeric"}
    )
  }
}
//# sourceMappingURL=application_view.js.map
