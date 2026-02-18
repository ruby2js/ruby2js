import { ApplicationRecord } from './application_record.js';
import { BroadcastChannel } from 'ruby2js-rails/targets/node/rails.js';
import { render } from "../views/clips/_clip.js";
import { hasOneAttached, hasManyAttached } from "juntos:active-storage";

export class Clip extends ApplicationRecord {
  static table_name = "clips";

  get audio() {
    return hasOneAttached(this, "audio")
  };

  validate() {
    return this.validates_presence_of("name")
  };
};

Clip.after_create_commit(async $record => (
  BroadcastChannel.broadcast(
    "clips",

    `<turbo-stream action="prepend" target="${"clips"}"><template>${await render({
      $context: {authenticityToken: "", flash: {}, contentFor: {}},
      clip: $record
    })}</template></turbo-stream>`
  )
));

Clip.after_update_commit(async $record => (
  BroadcastChannel.broadcast(
    "clips",

    `<turbo-stream action="replace" target="${`clip_${$record.id}`}"><template>${await render({
      $context: {authenticityToken: "", flash: {}, contentFor: {}},
      clip: $record
    })}</template></turbo-stream>`
  )
));

Clip.after_destroy_commit($record => (
  BroadcastChannel.broadcast(
    "clips",
    `<turbo-stream action="remove" target="${`clip_${$record.id}`}"></turbo-stream>`
  )
));

Clip.renderPartial = render