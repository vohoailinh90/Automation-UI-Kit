import * as React from "react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

type TaskStatus = "Chưa bắt đầu" | "Đang chạy" | "Trễ hạn" | "Hoàn thành"

type Task = {
  task: string
  project: string
  owner: string
  due: string
  status: TaskStatus
}

const tasks: Task[] = [
  { task: "Giải thích kỹ thuật cho khách hàng", project: "Valve Line A", owner: "Linh", due: "05/09", status: "Đang chạy" },
  { task: "Effort estimate cho ECR mới", project: "Injection Mold X2", owner: "Linh", due: "08/09", status: "Chưa bắt đầu" },
  { task: "Xây schedule baseline", project: "Fitting Series 9", owner: "Linh", due: "10/09", status: "Đang chạy" },
  { task: "Review thiết kế với R&D (Séc)", project: "Valve Line A", owner: "R&D CZ", due: "12/09", status: "Chưa bắt đầu" },
  { task: "Cập nhật tiến độ hàng tuần", project: "Injection Mold X2", owner: "Linh", due: "01/09", status: "Trễ hạn" },
  { task: "Xác nhận sample release", project: "Fitting Series 9", owner: "QA", due: "20/09", status: "Chưa bắt đầu" },
  { task: "Đóng milestone acquisition", project: "Valve Line A", owner: "Sales", due: "28/08", status: "Hoàn thành" },
]

const statusVariant: Record<TaskStatus, "default" | "secondary" | "destructive" | "success" | "outline"> = {
  "Chưa bắt đầu": "secondary",
  "Đang chạy": "default",
  "Trễ hạn": "destructive",
  "Hoàn thành": "success",
}

function TaskTable({ rows }: { rows: Task[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Task</TableHead>
          <TableHead>Dự án</TableHead>
          <TableHead>Phụ trách</TableHead>
          <TableHead>Hạn</TableHead>
          <TableHead className="text-right">Trạng thái</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((t) => (
          <TableRow key={t.task}>
            <TableCell className="font-medium">{t.task}</TableCell>
            <TableCell className="text-muted-foreground">{t.project}</TableCell>
            <TableCell className="text-muted-foreground">{t.owner}</TableCell>
            <TableCell className="text-muted-foreground">{t.due}</TableCell>
            <TableCell className="text-right">
              <Badge variant={statusVariant[t.status]}>{t.status}</Badge>
            </TableCell>
          </TableRow>
        ))}
        {rows.length === 0 && (
          <TableRow>
            <TableCell colSpan={5} className="py-8 text-center text-muted-foreground">
              Không có task nào.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  )
}

export function TasksPage() {
  const [query, setQuery] = React.useState("")

  const filtered = tasks.filter(
    (t) =>
      t.task.toLowerCase().includes(query.toLowerCase()) ||
      t.project.toLowerCase().includes(query.toLowerCase()),
  )

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between gap-4 space-y-0">
        <div>
          <CardTitle>Task &amp; Milestone tracker</CardTitle>
          <CardDescription>Theo dõi tiến độ các dự án đang phụ trách</CardDescription>
        </div>
        <div className="flex items-center gap-2">
          <Input
            placeholder="Tìm task hoặc dự án..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-56"
          />
          <Button>Thêm task</Button>
        </div>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="all">
          <TabsList>
            <TabsTrigger value="all">Tất cả</TabsTrigger>
            <TabsTrigger value="active">Đang chạy</TabsTrigger>
            <TabsTrigger value="late">Trễ hạn</TabsTrigger>
            <TabsTrigger value="done">Hoàn thành</TabsTrigger>
          </TabsList>
          <TabsContent value="all" className="mt-4">
            <TaskTable rows={filtered} />
          </TabsContent>
          <TabsContent value="active" className="mt-4">
            <TaskTable rows={filtered.filter((t) => t.status === "Đang chạy")} />
          </TabsContent>
          <TabsContent value="late" className="mt-4">
            <TaskTable rows={filtered.filter((t) => t.status === "Trễ hạn")} />
          </TabsContent>
          <TabsContent value="done" className="mt-4">
            <TaskTable rows={filtered.filter((t) => t.status === "Hoàn thành")} />
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}
