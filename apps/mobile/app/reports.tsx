import { Redirect } from 'expo-router';

export default function ReportsRedirect() {
  return <Redirect href={'/widgets' as never} />;
}
