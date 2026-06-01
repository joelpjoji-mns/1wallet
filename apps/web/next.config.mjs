/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: [
    '@1wallet/domain',
    '@1wallet/validation',
    '@1wallet/ui',
    '@1wallet/config',
    '@1wallet/ledger',
    '@1wallet/state',
  ],
};

export default nextConfig;
