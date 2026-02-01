// Main entry point for browser
import * as Turbo from '@hotwired/turbo';
import { Application } from '../config/routes.rb';
import '../app/javascript/controllers/index.js';
window.Turbo = Turbo;
Application.start();
