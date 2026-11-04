import type { NextConfig } from "next"

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  async redirects() {
    return [
      { source: "/en", destination: "/", permanent: true },
      { source: "/en/:path+", destination: "/:path+", permanent: true },
    ]
  },
  async rewrites() {
    // The homepage reaches /en after the public redirect and locale selection.
    return {
      beforeFiles: [
        { source: "/", destination: "/en" },
        { source: "/privacy", destination: "/en/privacy" },
      ],
    }
  },
  images: {
    formats: ["image/avif", "image/webp"],
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
}

export default nextConfig
