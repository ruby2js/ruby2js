import { ActiveRecord as Base, CollectionProxy } from 'ruby2js-rails/adapters/active_record_better_sqlite3.mjs';

export class ApplicationRecord extends Base {
  static primaryAbstractClass = true;
}

export { CollectionProxy };
