// Copyright (c) 2018, Brian Armstrong. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:channel_mock/channel_mock.dart';

// Extending ChannelMock is useful when you have a set of common items that you always
// want to mock whenever you are mocking a specific service.
class FirebaseAuthMock extends ChannelMock {
  FirebaseAuthMock()
      : super(FirebaseAuth.channel); // The channel is @visibleForTesting, so just use it

  var mockUserData = {
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
void main() {
  FirebaseAuthMock mock;

  setUp(() {
    mock = new FirebaseAuthMock();
  });

  test('it has already mocked the onAuthStateChanged listener', () async {
    // NOTE: no additional setup with the mock required

    // Use a Completer so we can wait on the results of `onAuthStateChanged`
    Completer doneListening = new Completer();

    // Trigger our code and complete with the found user
    FirebaseAuth.instance.onAuthStateChanged.then((user) {
      doneListening.complete(user);
    });

    // *magic*
    FirebaseUser user = await doneListening.future;
    expect(user.uid, equals('mock-uid'));
  });
}
