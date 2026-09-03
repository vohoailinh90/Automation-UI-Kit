import { LayoutDashboard, LineChart, ListChecks, Settings } from "lucide-react"

export const navItems = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard, end: true },
  { to: "/tasks", label: "Tasks", icon: ListChecks, end: false },
  { to: "/watchlist", label: "Watchlist", icon: LineChart, end: false },
  { to: "/settings", label: "Settings", icon: Settings, end: false },
] as const
