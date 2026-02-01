import { clips_path } from '../../../config/routes.js';
import { turbo_stream_from } from 'ruby2js-rails/targets/node/rails.js';
import * as _clip_module from './_clip.js';

export async function render({ $context, clips, lambda }) {
  let _buf = "";
  _buf += String(turbo_stream_from("clips"));
  _buf += "\n";
  _buf += "\n<div class=\"container mx-auto px-4 py-8\" data-controller=\"dictaphone\">\n  <h1 class=\"text-3xl font-bold mb-2\">Dictaphone</h1>\n  <p class=\"text-gray-600 mb-8\">Record audio and get automatic transcriptions powered by Whisper AI.</p>\n\n  <!-- Model loading status -->\n  <div data-dictaphone-target=\"status\" class=\"mb-6 p-4 bg-blue-50 text-blue-800 rounded-lg\">\n    Loading Whisper model...\n  </div>\n\n  <!-- Recording controls -->\n  <div class=\"mb-8 p-6 bg-gray-100 rounded-lg\">\n    <div class=\"flex gap-4 items-center mb-4\">\n      <button data-dictaphone-target=\"record\"\n              data-action=\"click->dictaphone#toggleRecording\"\n              disabled\n              class=\"bg-red-600 text-white px-6 py-3 rounded-full font-semibold hover:bg-red-700 transition disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2\">\n        <span data-dictaphone-target=\"recordIcon\">&#9679;</span>\n        <span data-dictaphone-target=\"recordLabel\">Record</span>\n      </button>\n\n      <!-- Recording timer -->\n      <span data-dictaphone-target=\"timer\" class=\"text-2xl font-mono text-gray-600 hidden\">\n        00:00\n      </span>\n\n      <!-- Audio level visualizer -->\n      <div data-dictaphone-target=\"visualizer\" class=\"flex-1 h-8 bg-gray-200 rounded hidden\">\n        <div data-dictaphone-target=\"level\" class=\"h-full bg-green-500 rounded transition-all duration-100\" style=\"width: 0%\"></div>\n      </div>\n    </div>\n\n    <!-- Playback and save form (shown after recording) -->\n    <div data-dictaphone-target=\"preview\" class=\"hidden\">\n      <audio data-dictaphone-target=\"audio\" controls class=\"w-full mb-4\"></audio>\n\n      <div data-dictaphone-target=\"transcribing\" class=\"mb-4 p-3 bg-yellow-50 text-yellow-800 rounded hidden\">\n        Transcribing audio...\n      </div>\n\n      ";
  _buf += `<form class="space-y-4" data-dictaphone-target="form" data-action="submit->dictaphone#save" action="${clips_path}" method="post">`;
  _buf += `<input type="hidden" name="authenticity_token" value="${$context.authenticityToken ?? ""}">\n`;
  _buf += "\n        <input type=\"hidden\" name=\"clip[duration]\" data-dictaphone-target=\"duration\">\n";
  _buf += "        <input type=\"hidden\" data-dictaphone-target=\"audioData\">\n\n        <div>\n          <label class=\"block text-sm font-medium text-gray-700 mb-1\">Name</label>\n          <input type=\"text\" name=\"clip[name]\"\n                 data-dictaphone-target=\"name\"\n                 placeholder=\"My recording\"\n                 class=\"w-full border rounded-lg p-3\">\n        </div>\n\n        <div>\n          <label class=\"block text-sm font-medium text-gray-700 mb-1\">Transcript</label>\n          <textarea name=\"clip[transcript]\"\n                    data-dictaphone-target=\"transcript\"\n                    rows=\"4\"\n                    placeholder=\"Transcription will appear here...\"\n                    class=\"w-full border rounded-lg p-3\"></textarea>\n        </div>\n\n        <div class=\"flex gap-4\">\n          ";
  _buf += "<input type=\"submit\" value=\"Save Clip\" class=\"bg-green-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-green-700 transition cursor-pointer\">";
  _buf += "\n";
  _buf += "          <button type=\"button\"\n                  data-action=\"click->dictaphone#discard\"\n                  class=\"bg-gray-400 text-white px-6 py-3 rounded-lg font-semibold hover:bg-gray-500 transition\">\n            Discard\n          </button>\n        </div>\n";
  _buf += "</form>";
  _buf += "    </div>\n  </div>\n\n  <!-- Clips list -->\n  <div>\n    <h2 class=\"text-xl font-semibold mb-4\">Your Clips</h2>\n    <div id=\"clips\" class=\"space-y-4\">\n      ";

  _buf += String((await Promise.all(clips.map(clip => (
    _clip_module.render({$context, clip})
  )))).join(""));

  _buf += "\n";
  _buf += "      <p id=\"empty-message\" class=\"text-gray-500 text-center py-12 hidden only:block\">\n        No clips yet. Record something to get started!\n      </p>\n    </div>\n  </div>\n</div>\n";
  return _buf
}