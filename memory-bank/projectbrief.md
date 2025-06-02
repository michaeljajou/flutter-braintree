# Flutter Braintree Plugin - Project Brief

## Project Overview

This is a Flutter plugin that wraps the native Braintree payment SDKs for both Android and iOS. The plugin provides two main functionalities:

1. **Drop-in UI**: Launch Braintree's native payment UI
2. **Custom UI**: Allow developers to create custom Flutter UIs with Braintree functionality

## Current Status

- **Version**: 4.0.0
- **Flutter SDK**: >=1.10.0
- **Dart SDK**: >=2.15.0 <4.0.0
- **Embeddings**: Already using Flutter embeddings v2

## Key Features

- Credit card tokenization
- PayPal payments
- Google Pay integration
- Venmo support
- 3D Secure authentication
- Device data collection

## Architecture

- **Main Plugin Class**: `FlutterBraintreePlugin` (handles custom functionality)
- **Drop-in Plugin Class**: `FlutterBraintreeDropIn` (handles drop-in UI)
- **Custom Activity**: `FlutterBraintreeCustom` (Android custom payment flows)
- **Drop-in Activity**: `DropInActivity` (Android drop-in wrapper)

## Current Implementation State

The plugin already implements Flutter embeddings v2 properly with:

- `FlutterPlugin` interface implementation
- `ActivityAware` interface implementation
- Proper lifecycle management (`onAttachedToEngine`, `onAttachedToActivity`, etc.)
- Both v1 (`registerWith`) and v2 methods for backward compatibility

## User Request

Update the plugin to use Flutter embeddings v2 - however, analysis shows it already does. The request likely stems from wanting to:

1. Remove v1 compatibility code
2. Ensure full modernization
3. Clean up deprecated patterns
4. Optimize for v2-only usage
