/// The official BetterCast server, used unless the user picks their own.
const kOfficialServer = String.fromEnvironment(
  'BETTERCAST_SERVER',
  defaultValue: 'https://bettercast.gameanddev.cloud',
);

/// Guide for running your own server.
const kSelfHostGuideUrl =
    'https://github.com/polo5922/BetterCast/blob/main/SELF_HOSTING.md';
