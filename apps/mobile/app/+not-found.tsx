import { router } from 'expo-router';
import { RecoveryState } from '../src/components/Brand';

export default function NotFound() {
  return (
    <RecoveryState
      title="Screen not found"
      body="That link does not point to a current 1wallet screen."
      actionLabel="Go home"
      onAction={() => router.replace('/' as never)}
    />
  );
}
