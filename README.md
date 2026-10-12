# JARVIS ROG Edition

A black-and-red Flutter voice assistant with an animated status orb, speech
recognition, spoken replies, and Groq chat completions.

## Run

From the project root:

```sh
cd artifacts/jarvis-rog
flutter pub get
flutter run
```

To pass the Replit Secret as a build-time fallback, run this from the Replit
environment:

```sh
flutter run --dart-define=GROQ_API_KEY="$GROQ_API_KEY"
```

A key saved on the device takes priority over the build-time value. You can
also open **Settings**, paste a key, and save it to Android encrypted storage
or the iOS Keychain. Settings includes a **Test Groq Connection** action. The
model can also be changed there; the default is
`llama-3.3-70b-versatile`.

After setup, tap the microphone, speak, and pause or tap again to send the
transcript. JARVIS sends the conversation to Groq and reads the reply aloud.

## Permissions

- Android: microphone recording and internet access.
- iOS: microphone and speech-recognition permission prompts.

The Groq key is not included in the source code. A build-time `--dart-define`
is compiled into the app binary, and any key used by a client app could be
inspected by someone with control of the device or its network traffic.
