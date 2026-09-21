import * as React from "react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
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
  id: string
  task: string
  project: string
  owner: string
  due: string
  status: TaskStatus
}

const statuses: TaskStatus[] = ["Chưa bắt đầu", "Đang chạy", "Trễ hạn", "Hoàn thành"]

const initialTasks: Task[] = [
  { id: "t1", task: "Giải thích kỹ thuật cho khách hàng", project: "Valve Line A", owner: "Linh", due: "05/09", status: "Đang chạy" },
  { id: "t2", task: "Effort estimate cho ECR mới", project: "Injection Mold X2", owner: "Linh", due: "08/09", status: "Chưa bắt đầu" },
  { id: "t3", task: "Xây schedule baseline", project: "Fitting Series 9", owner: "Linh", due: "10/09", status: "Đang chạy" },
  { id: "t4", task: "Review thiết kế với R&D (Séc)", project: "Valve Line A", owner: "R&D CZ", due: "12/09", status: "Chưa bắt đầu" },
  { id: "t5", task: "Cập nhật tiến độ hàng tuần", project: "Injection Mold X2", owner: "Linh", due: "01/09", status: "Trễ hạn" },
  { id: "t6", task: "Xác nhận sample release", project: "Fitting Series 9", owner: "QA", due: "20/09", status: "Chưa bắt đầu" },
  { id: "t7", task: "Đóng milestone acquisition", project: "Valve Line A", owner: "Sales", due: "28/08", status: "Hoàn thành" },
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
          <TableRow key={t.id}>
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

function AddTaskDialog({
  open,
  onOpenChange,
  onAdd,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  onAdd: (task: Omit<Task, "id">) => void
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        {/* Radix unmount nội dung khi dialog đóng, nên form tự reset ở lần mở sau. */}
        <AddTaskForm onAdd={onAdd} onDone={() => onOpenChange(false)} />
      </DialogContent>
    </Dialog>
  )
}

function AddTaskForm({
  onAdd,
  onDone,
}: {
  onAdd: (task: Omit<Task, "id">) => void
  onDone: () => void
}) {
  const [task, setTask] = React.useState("")
  const [project, setProject] = React.useState("")
  const [owner, setOwner] = React.useState("")
  const [due, setDue] = React.useState("")
  const [status, setStatus] = React.useState<TaskStatus>("Chưa bắt đầu")

  const canSubmit = task.trim() !== "" && project.trim() !== ""

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!canSubmit) return
    onAdd({
      task: task.trim(),
      project: project.trim(),
      owner: owner.trim() || "Chưa gán",
      due: due.trim() || "—",
      status,
    })
    onDone()
  }

  return (
    <form onSubmit={handleSubmit} className="grid gap-4">
      <DialogHeader>
        <DialogTitle>Thêm task</DialogTitle>
        <DialogDescription>
          Task được lưu trong bộ nhớ trình duyệt của phiên này — dữ liệu mẫu, chưa nối backend.
        </DialogDescription>
      </DialogHeader>

      <div className="grid gap-2">
        <Label htmlFor="task-name">Tên task</Label>
        <Input
          id="task-name"
          value={task}
          onChange={(e) => setTask(e.target.value)}
          placeholder="Ví dụ: Gửi báo giá cho khách"
          autoFocus
          required
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="grid gap-2">
          <Label htmlFor="task-project">Dự án</Label>
          <Input
            id="task-project"
            value={project}
            onChange={(e) => setProject(e.target.value)}
            placeholder="Valve Line A"
            required
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="task-owner">Phụ trách</Label>
          <Input
            id="task-owner"
            value={owner}
            onChange={(e) => setOwner(e.target.value)}
            placeholder="Linh"
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="task-due">Hạn</Label>
          <Input
            id="task-due"
            value={due}
            onChange={(e) => setDue(e.target.value)}
            placeholder="dd/mm"
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="task-status">Trạng thái</Label>
          <Select value={status} onValueChange={(value) => setStatus(value as TaskStatus)}>
            <SelectTrigger id="task-status" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {statuses.map((s) => (
                <SelectItem key={s} value={s}>
                  {s}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <DialogFooter>
        <DialogClose asChild>
          <Button type="button" variant="outline">
            Huỷ
          </Button>
        </DialogClose>
        <Button type="submit" disabled={!canSubmit}>
          Thêm task
        </Button>
      </DialogFooter>
    </form>
  )
}

export function TasksPage() {
  const [query, setQuery] = React.useState("")
  const [tasks, setTasks] = React.useState<Task[]>(initialTasks)
  const [addOpen, setAddOpen] = React.useState(false)

  const filtered = tasks.filter(
    (t) =>
      t.task.toLowerCase().includes(query.toLowerCase()) ||
      t.project.toLowerCase().includes(query.toLowerCase()),
  )

  function handleAdd(task: Omit<Task, "id">) {
    setTasks((prev) => [{ ...task, id: crypto.randomUUID() }, ...prev])
  }

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
            aria-label="Tìm task hoặc dự án"
          />
          <Button onClick={() => setAddOpen(true)}>Thêm task</Button>
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

      <AddTaskDialog open={addOpen} onOpenChange={setAddOpen} onAdd={handleAdd} />
    </Card>
  )
}
