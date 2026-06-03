const path = require('path');

const workspaceNodeModules = path.resolve(__dirname, '../../node_modules');

module.exports = {
  dependencies: {
    '@react-native-async-storage/async-storage': {
      root: path.join(workspaceNodeModules, '@react-native-async-storage/async-storage'),
    },
    'react-native-safe-area-context': {
      root: path.join(workspaceNodeModules, 'react-native-safe-area-context'),
    },
    'react-native-screens': {
      root: path.join(workspaceNodeModules, 'react-native-screens'),
    },
    'react-native-get-sms-android': {
      platforms: {
        ios: null,
      },
    },
  },
};
