import { TriangleAlert } from "lucide-react"
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
  DialogTrigger,
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
import { useTasks } from "@/components/tasks-provider"
import { taskStatuses, type Task, type TaskStatus } from "@/lib/tasks"

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

function AddTaskDialog({ onAdd }: { onAdd: (task: Omit<Task, "id">) => void }) {
  const [open, setOpen] = React.useState(false)

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      {/* Nút mở phải nằm trong DialogTrigger thì Radix mới trả focus về đúng nó khi đóng. */}
      <DialogTrigger asChild>
        <Button>Thêm task</Button>
      </DialogTrigger>
      <DialogContent>
        {/* Radix unmount nội dung khi dialog đóng, nên form tự reset ở lần mở sau. */}
        <AddTaskForm onAdd={onAdd} onDone={() => setOpen(false)} />
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
              {taskStatuses.map((s) => (
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
  const { tasks, addTask, storageBlocked } = useTasks()

  const filtered = tasks.filter(
    (t) =>
      t.task.toLowerCase().includes(query.toLowerCase()) ||
      t.project.toLowerCase().includes(query.toLowerCase()),
  )

  return (
    <div className="flex flex-col gap-6">
      <p aria-live="polite">
        {storageBlocked && (
          <span className="flex items-center gap-2 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
            <TriangleAlert className="size-4 shrink-0" />
            Không lưu được vào bộ nhớ phiên — task vẫn hiện ở đây nhưng sẽ mất nếu tải lại trang.
          </span>
        )}
      </p>

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
            <AddTaskDialog onAdd={addTask} />
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
    </div>
  )
}
