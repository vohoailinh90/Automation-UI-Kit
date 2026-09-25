import {
  ChartPie,
  FlaskConical,
  LayoutDashboard,
  LineChart,
  ListChecks,
  Settings,
  Workflow,
  type LucideIcon,
} from "lucide-react"

export type NavItem = { to: string; label: string; icon: LucideIcon; end: boolean }

export type NavGroup = { label: string | null; items: NavItem[] }

/**
 * Menu chia nhóm: nhóm "Dashboard mẫu" là các template dựng sẵn để copy sang
 * repo khác, tách riêng khỏi các trang công cụ để người mở kit biết ngay đâu là
 * thứ để lấy về dùng.
 */
export const navGroups: NavGroup[] = [
  {
    label: null,
    items: [
      { to: "/", label: "Dashboard", icon: LayoutDashboard, end: true },
      { to: "/tasks", label: "Tasks", icon: ListChecks, end: false },
      { to: "/watchlist", label: "Watchlist", icon: LineChart, end: false },
    ],
  },
  {
    label: "Dashboard mẫu",
    items: [
      { to: "/automation", label: "Automation", icon: Workflow, end: false },
      { to: "/orders", label: "Orders", icon: FlaskConical, end: false },
      { to: "/portfolio", label: "Portfolio", icon: ChartPie, end: false },
    ],
  },
  {
    label: null,
    items: [{ to: "/settings", label: "Settings", icon: Settings, end: false }],
  },
]

export const navItems: NavItem[] = navGroups.flatMap((group) => group.items)
