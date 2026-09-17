// Firebase Cloud Messaging service worker — handles web push while the
// GSUhub admin tab is backgrounded or closed.
//
// This file is served as-is from the web root and runs outside the Flutter
// app, so it cannot read Dart's --dart-define values. Its config is
// supplied at runtime instead: the app posts it in via postMessage (see
// web/index.html), and the worker waits for that before initializing.
//
// That indirection exists so no Firebase project values are hardcoded
// here. A committed service worker containing a real project id would put
// project-specific configuration into version control, which the rest of
// the project deliberately avoids.

importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js',
);

let messagingInitialized = false;

self.addEventListener('message', (event) => {
  if (messagingInitialized) return;
  if (!event.data || event.data.type !== 'FIREBASE_CONFIG') return;

  try {
    firebase.initializeApp(event.data.config);
    const messaging = firebase.messaging();
    messagingInitialized = true;

    messaging.onBackgroundMessage((payload) => {
      const notification = payload.notification || {};
      const data = payload.data || {};

      self.registration.showNotification(
        notification.title || 'GSUhub',
        {
          body: notification.body || '',
          icon: '/icons/Icon-192.png',
          // Carried through so a click can deep-link to the report or
          // work order the notification is about.
          data: data,
          tag: data.relatedEntityId || undefined,
        },
      );
    });
  } catch (error) {
    // A service worker that throws during setup is silently dead, which
    // presents as "web push just does not work" with nothing in the
    // console. Log loudly instead.
    console.error('GSUhub: failed to initialize messaging worker', error);
  }
});

// Focus an existing GSUhub tab if one is open rather than opening a
// duplicate, then hand it the notification payload to route on.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if ('focus' in client) {
            client.postMessage({
              type: 'NOTIFICATION_CLICK',
              data: event.notification.data,
            });
            return client.focus();
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow('/');
        }
      }),
  );
});
