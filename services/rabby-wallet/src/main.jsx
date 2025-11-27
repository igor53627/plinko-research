import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

// App version - update this when releasing new versions
export const APP_VERSION = '1.3.0';

// Log version on startup with upgrade detection
const VERSION_STORAGE_KEY = 'rabby-plinko-version';
const previousVersion = localStorage.getItem(VERSION_STORAGE_KEY);

if (previousVersion && previousVersion !== APP_VERSION) {
  console.log(`🚀 Rabby Plinko PIR upgraded: ${previousVersion} → ${APP_VERSION}`);
} else if (!previousVersion) {
  console.log(`🚀 Rabby Plinko PIR v${APP_VERSION} (first run)`);
} else {
  console.log(`🚀 Rabby Plinko PIR v${APP_VERSION}`);
}

localStorage.setItem(VERSION_STORAGE_KEY, APP_VERSION);

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
