import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useEffect, useState } from 'react';
import { Image, StyleSheet, View } from 'react-native';
import { Text, TouchableRipple, useTheme } from 'react-native-paper';

export function UserProfileButton({
  email,
  displayName,
  photoUrl,
  onPress,
}: {
  email?: string;
  displayName?: string;
  photoUrl?: string;
  onPress: () => void;
}) {
  const theme = useTheme();
  const [imageFailed, setImageFailed] = useState(false);
  const initials = initialsFromName(displayName, email);
  const showPhoto = Boolean(photoUrl && !imageFailed);

  useEffect(() => {
    setImageFailed(false);
  }, [photoUrl]);

  return (
    <TouchableRipple
      borderless
      onPress={onPress}
      style={[styles.avatar, { backgroundColor: theme.colors.primaryContainer }]}
    >
      <View style={styles.avatarInner}>
        {showPhoto ? (
          <Image
            source={{ uri: photoUrl }}
            resizeMode="contain"
            style={styles.avatarPhoto}
            onError={() => setImageFailed(true)}
          />
        ) : initials ? (
          <Text variant="labelLarge" style={{ color: theme.colors.onPrimaryContainer }}>
            {initials}
          </Text>
        ) : (
          <MaterialCommunityIcons
            name="account-circle-outline"
            size={24}
            color={theme.colors.onPrimaryContainer}
          />
        )}
      </View>
    </TouchableRipple>
  );
}

function initialsFromName(displayName?: string, email?: string): string | undefined {
  const name = (displayName || email?.split('@')[0])?.replace(/[._-]+/g, ' ').trim();
  if (!name) return undefined;
  return name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('');
}

const styles = StyleSheet.create({
  avatar: {
    width: 40,
    height: 40,
    borderRadius: tokens.radius.pill,
    overflow: 'hidden',
    marginRight: 8,
  },
  avatarInner: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  avatarPhoto: { width: '100%', height: '100%' },
});
