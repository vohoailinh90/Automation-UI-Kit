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

/**
 * `readFailed` chỉ bật khi *không đọc được* storage — lúc đó ta không biết
 * trong đó đang có gì, nên ghi đè sẽ làm mất dữ liệu thật. Dữ liệu đọc được
 * nhưng hỏng (JSON sai, không phải array, entry sai kiểu) thì không tính:
 * ta đã thấy nó là rác, đè lên rác là an toàn.
 */
export function loadTasks(): { tasks: Task[]; readFailed: boolean } {
  let raw: string | null
  try {
    raw = sessionStorage.getItem(TASKS_STORAGE_KEY)
  } catch {
    return { tasks: initialTasks, readFailed: true }
  }

  if (!raw) return { tasks: initialTasks, readFailed: false }

  try {
    const parsed: unknown = JSON.parse(raw)
    if (!Array.isArray(parsed)) return { tasks: initialTasks, readFailed: false }
    const valid = parsed.filter(isTask)
    return { tasks: valid.length > 0 ? valid : initialTasks, readFailed: false }
  } catch {
    return { tasks: initialTasks, readFailed: false }
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
