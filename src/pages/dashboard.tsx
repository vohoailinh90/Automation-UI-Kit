import { CheckCircle2, FolderKanban, TrendingUp, Wallet } from "lucide-react"
import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"

import { StatCard } from "@/components/stat-card"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"

const progressData = [
  { week: "T1", planned: 20, actual: 18 },
  { week: "T2", planned: 35, actual: 30 },
  { week: "T3", planned: 48, actual: 44 },
  { week: "T4", planned: 60, actual: 61 },
  { week: "T5", planned: 74, actual: 70 },
  { week: "T6", planned: 88, actual: 86 },
  { week: "T7", planned: 100, actual: 94 },
]

const milestones = [
  { name: "Acquisition kickoff", project: "Valve Line A", status: "Done" as const },
  { name: "Effort estimate submitted", project: "Injection Mold X2", status: "Done" as const },
  { name: "ECR review with khách hàng", project: "Valve Line A", status: "In progress" as const },
  { name: "Schedule baseline lock", project: "Fitting Series 9", status: "Upcoming" as const },
  { name: "Sample release", project: "Injection Mold X2", status: "Upcoming" as const },
]

const statusVariant = {
  Done: "success",
  "In progress": "default",
  Upcoming: "outline",
} as const

export function DashboardPage() {
  return (
    <div className="flex flex-col gap-6">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Dự án đang chạy"
          value="6"
          hint="+1 so với tháng trước"
          icon={FolderKanban}
          trend="up"
        />
        <StatCard
          label="Task đang mở"
          value="23"
          hint="5 task quá hạn"
          icon={CheckCircle2}
          trend="down"
        />
        <StatCard
          label="Milestone tuần này"
          value="4"
          hint="1 đã hoàn thành"
          icon={TrendingUp}
          trend="neutral"
        />
        <StatCard
          label="Portfolio P/L (tháng)"
          value="+3.2%"
          hint="JP + US, tham khảo"
          icon={Wallet}
          trend="up"
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle>Tiến độ dự án theo tuần</CardTitle>
            <CardDescription>Kế hoạch (planned) so với thực tế (actual), % hoàn thành</CardDescription>
          </CardHeader>
          <CardContent className="h-64 px-2 sm:px-6">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={progressData} margin={{ left: 0, right: 12, top: 8, bottom: 0 }}>
                <defs>
                  <linearGradient id="planned" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="var(--chart-1)" stopOpacity={0.35} />
                    <stop offset="95%" stopColor="var(--chart-1)" stopOpacity={0.02} />
                  </linearGradient>
                  <linearGradient id="actual" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="var(--chart-2)" stopOpacity={0.35} />
                    <stop offset="95%" stopColor="var(--chart-2)" stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" vertical={false} className="stroke-border" />
                <XAxis dataKey="week" tickLine={false} axisLine={false} fontSize={12} />
                <YAxis tickLine={false} axisLine={false} fontSize={12} width={44} unit="%" />
                <Tooltip
                  contentStyle={{
                    borderRadius: 8,
                    border: "1px solid var(--border)",
                    background: "var(--popover)",
                    color: "var(--popover-foreground)",
                    fontSize: 12,
                  }}
                  formatter={(value, name) => [
                    typeof value === "number" ? `${value}%` : String(value ?? ""),
                    name,
                  ]}
                />
                <Legend
                  verticalAlign="top"
                  align="right"
                  height={28}
                  iconType="plainline"
                  iconSize={14}
                  wrapperStyle={{ fontSize: 12 }}
                />
                <Area
                  type="monotone"
                  dataKey="planned"
                  name="Kế hoạch"
                  stroke="var(--chart-1)"
                  fill="url(#planned)"
                  strokeWidth={2}
                />
                <Area
                  type="monotone"
                  dataKey="actual"
                  name="Thực tế"
                  stroke="var(--chart-2)"
                  fill="url(#actual)"
                  strokeWidth={2}
                />
              </AreaChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Milestone sắp tới</CardTitle>
            <CardDescription>Theo dõi các cột mốc quan trọng</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            {milestones.map((m, i) => (
              <div key={m.name}>
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{m.name}</p>
                    <p className="truncate text-xs text-muted-foreground">{m.project}</p>
                  </div>
                  <Badge variant={statusVariant[m.status]} className="shrink-0">
                    {m.status}
                  </Badge>
                </div>
                {i < milestones.length - 1 && <Separator className="mt-3" />}
              </div>
            ))}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
