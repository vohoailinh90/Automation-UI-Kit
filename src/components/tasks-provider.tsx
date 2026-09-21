import * as React from "react"

import { loadTasks, persistTasks, type Task } from "@/lib/tasks"
import { createId } from "@/lib/utils"

/** `"read"`: không đọc được storage. `"write"`: đọc được nhưng ghi hỏng. */
export type StorageIssue = "read" | "write" | null

type TasksState = {
  tasks: Task[]
  addTask: (task: Omit<Task, "id">) => void
  storageIssue: StorageIssue
}

const TasksContext = React.createContext<TasksState | null>(null)

/**
 * State nằm trên route nên chuyển trang không unmount nó — không phụ thuộc vào
 * việc ghi storage có thành công hay không. sessionStorage chỉ thêm khả năng
 * sống sót qua reload.
 *
 * Nếu lần đọc đầu đã hỏng thì ta không biết storage đang chứa gì, nên nhịn ghi
 * cho tới khi người dùng tải lại trang — ghi lúc này sẽ đè dữ liệu thật bằng
 * dữ liệu mẫu đang hiển thị.
 */
export function TasksProvider({ children }: { children: React.ReactNode }) {
  const [initial] = React.useState(loadTasks)
  const [tasks, setTasks] = React.useState<Task[]>(initial.tasks)
  const [writeFailed, setWriteFailed] = React.useState(false)

  const latest = React.useRef(initial.tasks)
  const readFailed = initial.readFailed

  const addTask = React.useCallback(
    (task: Omit<Task, "id">) => {
      const next = [{ ...task, id: createId() }, ...latest.current]
      latest.current = next
      setTasks(next)
      if (readFailed) return
      setWriteFailed(!persistTasks(next))
    },
    [readFailed],
  )

  const storageIssue: StorageIssue = readFailed ? "read" : writeFailed ? "write" : null

  const value = React.useMemo(
    () => ({ tasks, addTask, storageIssue }),
    [tasks, addTask, storageIssue],
  )

  return <TasksContext.Provider value={value}>{children}</TasksContext.Provider>
}

export function useTasks() {
  const context = React.useContext(TasksContext)
  if (!context) throw new Error("useTasks must be used within a TasksProvider")
  return context
}
