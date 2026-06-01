require('./src/installExpoRuntimeGlobals');
require('@expo/metro-runtime');
require('react-native-gesture-handler');

const { ExpoRoot } = require('expo-router');
const { Head } = require('expo-router/build/head');
const { renderRootComponent } = require('expo-router/build/renderRootComponent');
const React = require('react');
const { AppRegistry } = require('react-native');
const { processIncomingSmsHeadlessTask } = require('./src/autoCaptureSmsTask');

AppRegistry.registerHeadlessTask('OneWalletSmsReceived', () => processIncomingSmsHeadlessTask);

const ctx = require.context(
  './app',
  true,
  /^(?:\.\/)(?!(?:(?:(?:.*\+api)|(?:\+html)))\.[tj]sx?$).*(?:\.ios|\.web)?\.[tj]sx?$/,
  'sync',
);

function App() {
  return React.createElement(Head.Provider, null, React.createElement(ExpoRoot, { context: ctx }));
}

renderRootComponent(App);
