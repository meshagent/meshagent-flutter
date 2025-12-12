# Meshagent Flutter example

This example shows how to connect to a Meshagent room from a Flutter app using
`RoomConnectionScope`. Replace the placeholder values in `lib/main.dart` with a
room JWT, project ID, and room name from your Meshagent project.

## Running the example

1. Install Flutter 3.24 or newer.
2. From this folder, fetch dependencies:

   ```bash
   flutter pub get
   ```

3. Run the app (Chrome is the simplest target when testing locally):

   ```bash
   flutter run -d chrome
   ```

If you prefer to generate JWTs during development, swap `staticAuthorization`
for `developmentAuthorization` in `lib/main.dart` and provide your API key ID
and secret.