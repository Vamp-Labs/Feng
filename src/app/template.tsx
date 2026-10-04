import { PageEnter } from "@/components/motion/page-enter";

export default function Template({ children }: { children: React.ReactNode }) {
  return <PageEnter>{children}</PageEnter>;
}
