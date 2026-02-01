export function layout(context, content) {
  let _buf = "";
  _buf += "<!DOCTYPE html>\n<html>\n  <head>\n    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">\n    <style>\n      /* Email styles need to be inline */\n    </style>\n  </head>\n\n  <body>\n    ";
  _buf += String(content);
  _buf += "\n";
  _buf += "  </body>\n</html>\n";
  return _buf
}