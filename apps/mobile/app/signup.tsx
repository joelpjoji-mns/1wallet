import { Redirect } from 'expo-router';

export default function Signup() {
  return <Redirect href={'/login?mode=create' as never} />;
}
