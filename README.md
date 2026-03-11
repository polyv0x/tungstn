<p align="center" style="padding-top:20px">

Tungstn is a privacy first evolution of Commet chat for the Matrix protocol.  [Matrix](https://matrix.org) focused on providing a feature rich experience while maintaining a simple interface. The goal is to build a secure, privacy respecting app without compromising on the features you have come to expect from a modern chat client.

# Features
- Supports **Windows**, **Linux**, and **Android** (MacOS and iOS planned in future)
- End-to-End Encryption
- Custom Emoji + Stickers
- Tenor compatible API GIF Search (self hosted possible)
- Threads
- Encrypted Room Search
- Multiple Accounts
- Spaces
- Emoji verification & cross signing
- Push Notifications
- URL Preview


# Translation
Help translate Tungstn to your language on [Weblate](https://hosted.weblate.org/)

# Development
Tungstn is built using [Flutter](https://flutter.dev), currently v3.41.1 

This repo currently has a monorepo structure, containing two flutter projects: Tungstn and Tiamat. Tungstn is the main client, and Tiamat is a sort of wrapper around Material with some extra goodies, which is used to maintain a consistent style across the app. Tiamat may eventually be moved to its own repo, but for now it is maintained here for ease of development.

