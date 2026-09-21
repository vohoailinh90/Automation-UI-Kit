export type TaskStatus = "Chưa bắt đầu" | "Đang chạy" | "Trễ hạn" | "Hoàn thành"

export type Task = {
  id: string
  task: string
  project: string
  owner: string
  due: string
  status: TaskStatus
}

export const taskStatuses: TaskStatus[] = [
  "Chưa bắt đầu",
  "Đang chạy",
  "Trễ hạn",
  "Hoàn thành",
]

export const TASKS_STORAGE_KEY = "automation-ui-kit-tasks"

export const initialTasks: Task[] = [
  { id: "t1", task: "Giải thích kỹ thuật cho khách hàng", project: "Valve Line A", owner: "Linh", due: "05/09", status: "Đang chạy" },
  { id: "t2", task: "Effort estimate cho ECR mới", project: "Injection Mold X2", owner: "Linh", due: "08/09", status: "Chưa bắt đầu" },
  { id: "t3", task: "Xây schedule baseline", project: "Fitting Series 9", owner: "Linh", due: "10/09", status: "Đang chạy" },
  { id: "t4", task: "Review thiết kế với R&D (Séc)", project: "Valve Line A", owner: "R&D CZ", due: "12/09", status: "Chưa bắt đầu" },
  { id: "t5", task: "Cập nhật tiến độ hàng tuần", project: "Injection Mold X2", owner: "Linh", due: "01/09", status: "Trễ hạn" },
  { id: "t6", task: "Xác nhận sample release", project: "Fitting Series 9", owner: "QA", due: "20/09", status: "Chưa bắt đầu" },
  { id: "t7", task: "Đóng milestone acquisition", project: "Valve Line A", owner: "Sales", due: "28/08", status: "Hoàn thành" },
]

/** Mọi trường phải đúng kiểu: `owner: {}` lọt qua sẽ làm React ném lỗi lúc render. */
export function isTask(value: unknown): value is Task {
  const t = value as Task
  return (
    typeof t === "object" &&
    t !== null &&
    typeof t.id === "string" &&
    typeof t.task === "string" &&
    typeof t.project === "string" &&
    typeof t.owner === "string" &&
    typeof t.due === "string" &&
    taskStatuses.includes(t.status)
  )
}

export function loadTasks(): Task[] {
  try {
    const raw = sessionStorage.getItem(TASKS_STORAGE_KEY)
    if (!raw) return initialTasks
    const parsed: unknown = JSON.parse(raw)
    if (!Array.isArray(parsed)) return initialTasks
    const valid = parsed.filter(isTask)
    return valid.length > 0 ? valid : initialTasks
  } catch {
    // sessionStorage bị chặn hoặc JSON hỏng — quay về dữ liệu mẫu.
    return initialTasks
  }
}

/** Trả về `false` khi trình duyệt chặn storage hoặc hết quota, để UI báo đúng. */
export function persistTasks(next: Task[]) {
  try {
    sessionStorage.setItem(TASKS_STORAGE_KEY, JSON.stringify(next))
    return true
  } catch {
    return false
  }
}
