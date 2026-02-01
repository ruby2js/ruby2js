import { clip_path } from '../../../config/routes.js';
import { dom_id } from 'ruby2js-rails/targets/node/rails.js';

export async function render({ $context, clip }) {
  let _buf = "";
  _buf += "<div id=\"";
  _buf += String(dom_id(clip));
  _buf += "\" class=\"bg-white rounded-lg shadow-md p-4\">\n  <div class=\"flex justify-between items-start mb-3\">\n    <div>\n      <h3 class=\"font-semibold text-lg\">";
  _buf += String(clip.name);
  _buf += "</h3>\n      <span class=\"text-gray-500 text-sm\">\n        ";
  _buf += String(clip.created_at.strftime("%b %d, %Y at %H:%M"));
  _buf += "\n";
  _buf += "        ";

  if (clip.duration) {
    _buf += "          &middot; ";
    _buf += String(Math.round(clip.duration * 10 ** 1) / 10 ** 1);
    _buf += "s\n"
  };

  _buf += "      </span>\n    </div>\n    ";
  _buf += `<form class="button_to" method="post" action="${clip_path(clip)}"><input type="hidden" name="_method" value="delete"><button class="text-gray-400 hover:text-red-600" data-turbo-confirm="Delete this clip?" type="submit"><svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">\n        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />\n      </svg></button><input type="hidden" name="authenticity_token" value="${$context.authenticityToken ?? ""}"></form>`;
  _buf += "  </div>\n\n";

  if (await clip.audio.attached()) {
    _buf += "    <audio controls class=\"w-full mb-3\">\n      <source src=\"";
    _buf += String(await clip.audio.url());
    _buf += "\" type=\"";
    _buf += String(await clip.audio.content_type());
    _buf += "\">\n    </audio>\n"
  };

  _buf += "\n";

  if (clip.transcript.present) {
    _buf += "    <div class=\"bg-gray-50 rounded p-3\">\n      <p class=\"text-gray-700 text-sm\">";
    _buf += String(clip.transcript);
    _buf += "</p>\n    </div>\n"
  } else {
    _buf += "    <p class=\"text-gray-400 text-sm italic\">No transcript available</p>\n"
  };

  _buf += "</div>\n";
  return _buf
}