## 1.4.0

Swapped out lock library to get reentrancy

## 1.3.0

Message header is now like [len, (len ^ -1).reverse()] .  Maybe this oughtta be a major version increment?  That feels weird, though.

## 1.2.0

Added some checks and options for robustness.  Also fixed some fatal bugs.

## 1.1.2

Checksum bugfix

## 1.1.1

Tweaks to possibly consolidate packets

## 1.1.0

Message header is now like [length, length ^ -1], for checksum

## 1.0.7

Trying again

## 1.0.6

Fixed a pointless error

## 1.0.5

Tweaked docs and added `clearOldScans`.

## 1.0.4

`connect` blocked forever if all connections failed; no longer.

## 1.0.3

Fixed broadcast disconnection handling

## 1.0.2

Ok, maybe NOW the disconnect handling is correct?

## 1.0.1

Fixed a few unawaited futures

## 1.0.0

Added autoping, and I think I made disconnection detection more robust, so, 1.0.0 now

## 0.9.1

Fixed some bugs in the examples; I think they all work, now

## 0.9.0

Most of it works - I think raw sockets may not work, and I'm working out some bugginess possibly relating to Android.
