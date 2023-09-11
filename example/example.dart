// Copyright (c) 2018, Brian Armstrong. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:channel_mock/channel_mock.dart';

/* -------------------------------- */
/* Example of extending ChannelMock */
/* -------------------------------- */

// Extending ChannelMock is useful when you have a set of common items that you always
// want to mock whenever you are mocking a specific service.
class FirebaseAuthMock extends ChannelMock {
  FirebaseAuthMock() : super(MethodChannel('plugins.flutter.io/firebase_auth'));

  final mockUserData = {
    'uid': 'mock-uid',
    'providerData': [
      {
        'providerId': 'mock-provider',
        'uid': 'mock-provider-id',
      },
    ],
  };

  @override
  void reset() {
    super.reset();

    when('currentUser').thenReturn(mockUserData);
    when('getIdToken').thenReturn(mockUserData['uid']);

    when('startListeningAuthState').thenRespond(
      'onAuthStateChanged',
      (handle, _) => <String, dynamic>{
        'id': handle,
        'user': mockUserData,
      },
    );

    otherwise().thenReturn(mockUserData);
  }
}

// Then it is simple to use in tests
void mainExt() {
  final mock = new FirebaseAuthMock();

  setUp(() {
    mock.reset();
  });

  test('it has already mocked the onAuthStateChanged listener', () async {
    // NOTE: no additional setup with the mock required

    // Use a Completer so we can wait on the results of `onAuthStateChanged`
    final doneListening = new Completer<User?>();

    // Trigger our code and complete with the found user
    FirebaseAuth.instance.authStateChanges().listen((user) {
      doneListening.complete(user);
    });

    // *magic*
    final user = await doneListening.future;
    expect(user, isNotNull);
    expect(user!.uid, equals('mock-uid'));
  });
}

/* ----------------------------- */
/* Example implement ChannelMock */
/* ----------------------------- */

// This library is meant for mocking flutter method channels during unit tests
// This example file is of a mock for FirebaseAuth
void mainImpl() {
  const channel = const MethodChannel(
    'plugins.flutter.io/firebase_auth',
  );

  late ChannelMock mock;

  final mockUserData = {
    'uid': 'mock-uid',
    'providerData': [
      {
        'providerId': 'mock-provider',
        'uid': 'mock-provider-id',
      },
    ],
  };

  setUp(() {
    // This is all it takes, then we just need to use our methods
    mock = new ChannelMock(channel);
  });

  test('Simple return value', () async {
    // Whenever the 'getIdToken' method is called, it will return our mock token
    mock.when('currentUser').thenReturn(mockUserData);

    final user = FirebaseAuth.instance.currentUser;
    expect(user, isNotNull);
    expect(user!.uid, equals('mock-uid'));
  });

  test('Mock a platform response after a call', () async {
    // With FirebaseAuth, a platform message is required for an auth state change to happen
    // So when we start listening, we have to emulate this platform call
    mock.when('startListeningAuthState').thenRespond(
        'authStateChanges',
        (handle, _) => <String, dynamic>{
              'id': handle,
              'user': mockUserData,
            });

    // Use a Completer so we can wait on the results of `onAuthStateChanged`
    final doneListening = new Completer<User>();

    // Trigger our code and complete with the found user
    FirebaseAuth.instance.authStateChanges().listen((user) {
      doneListening.complete(user);
    });

    // *magic*
    final user = await doneListening.future;
    expect(user.uid, equals('mock-uid'));
  });

  test('Mock a google sign in', () async {
    mock.when('signInWithCredential').thenCall((handle, args) {
      // `handle` is an internally auto incremented number representing how many calls have been made
      // - it is often used internally with plugins for keeping data going down the right paths
      // `args` is whatever arguments were passed to `channel.invokeMethod`
      // - in this case, it's a Map<String, String>, but it varies by implementation
      Map newUser = Map.from(mockUserData);
      final cred = args as GoogleAuthCredential;
      newUser['email'] = '${cred.idToken}@${cred.accessToken}';

      // Whatever we return from this function is returned as if from `thenReturn`
      return newUser;
    });

    final result = await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(
        idToken: 'mock-id-token',
        accessToken: 'mock-access-token',
      ),
    );
    expect(result.user?.uid, equals('mock-uid'));
    expect(result.user?.email, equals('mock-id-token@mock-access-token'));
  });

  test('We just want most things to return the user', () async {
    // ChannelMock.otherwise is the default value to return if the MethodCall's method has not been mocked
    mock.otherwise().thenReturn(mockUserData);

    // Because we didn't mock this method specifically, it just returns the mock user data
    final user = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: 'mock-email',
      password: 'mock-password',
    );
    expect(user.user?.uid, equals('mock-uid'));
  });
}
