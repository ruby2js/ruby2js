export class ApplicationView extends Phlex.HTML {
  // Override in subclasses
  get title() {
    return "Blog"
  };

  // Helper: truncate text
  truncate(text, { length=100 } = {}) {
    if (!text) return "";
    return text.length > length ? `${text.slice(0, length)}...` : text
  };

  // Helper: format time ago
  time_ago(time) {
    if (!time) return "unknown";
    let seconds = (Date.now - time) / 1_000;

    if (seconds < 60) {
      return `${parseInt(seconds)}s ago`
    } else if (seconds < 3_600) {
      return `${parseInt(seconds / 60)}m ago`
    } else if (seconds < 86_400) {
      return `${parseInt(seconds / 3_600)}h ago`
    } else {
      return `${parseInt(seconds / 86_400)}d ago`
    }
  };

  // Helper: format date
  format_date(time) {
    if (!time) return "";
    let date = new Date(time);

    return date.toLocaleDateString(
      "en-US",
      {year: "numeric", month: "long", day: "numeric"}
    )
  }
}
//# sourceMappingURL=application_view.js.map
