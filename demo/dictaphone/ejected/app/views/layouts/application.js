import { stylesheetLinkTag } from "juntos:rails";

export function layout(context, content) {
  let _buf = "";
  _buf += "<!DOCTYPE html>\n<html>\n  <head>\n    <title>";
  _buf += String(context.contentFor.title || "" || "Dictaphone");
  _buf += "</title>\n    <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n    <meta name=\"apple-mobile-web-app-capable\" content=\"yes\">\n    <meta name=\"application-name\" content=\"Dictaphone\">\n    <meta name=\"mobile-web-app-capable\" content=\"yes\">\n    ";
  _buf += String(`<meta name="csrf-token" content="${context.authenticityToken ?? ""}">` ?? "");
  _buf += "\n";
  _buf += "    ";
  _buf += "";
  _buf += "\n";
  _buf += "\n    ";
  _buf += String(context.contentFor.head ?? "");
  _buf += "\n";
  _buf += "\n";
  _buf += "    ";
  _buf += "\n    <link rel=\"icon\" href=\"/icon.png\" type=\"image/png\">\n    <link rel=\"icon\" href=\"/icon.svg\" type=\"image/svg+xml\">\n    <link rel=\"apple-touch-icon\" href=\"/icon.png\">\n\n";
  _buf += "    ";
  _buf += String(stylesheetLinkTag("tailwind.css"));
  _buf += "\n";
  _buf += "    ";
  _buf += "";
  _buf += "\n";
  _buf += "  </head>\n\n  <body>\n    <main class=\"container mx-auto mt-28 px-5 flex\">\n      ";
  _buf += String(content);
  _buf += "\n";
  _buf += "    </main>\n  </body>\n</html>\n";
  return _buf
}