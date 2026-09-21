import * as React from "react"

import { loadTasks, persistTasks, type Task } from "@/lib/tasks"
import { createId } from "@/lib/utils"

type TasksState = {
  tasks: Task[]
  addTask: (task: Omit<Task, "id">) => void
  /** Ghi storage hỏng: task vẫn còn khi đổi route, nhưng reload là mất. */
  storageBlocked: boolean
}

const TasksContext = React.createContext<TasksState | null>(null)

/**
 * State nằm trên route nên chuyển trang không unmount nó — không phụ thuộc vào
 * việc ghi storage có thành công hay không. sessionStorage chỉ thêm khả năng
 * sống sót qua reload, và nếu ghi hỏng thì `storageBlocked` nói thẳng ra.
 */
export function TasksProvider({ children }: { children: React.ReactNode }) {
  const [tasks, setTasks] = React.useState<Task[]>(loadTasks)
  const [storageBlocked, setStorageBlocked] = React.useState(false)

  const latest = React.useRef(tasks)

  const addTask = React.useCallback((task: Omit<Task, "id">) => {
    const next = [{ ...task, id: createId() }, ...latest.current]
    latest.current = next
    setTasks(next)
    setStorageBlocked(!persistTasks(next))
  }, [])

  const value = React.useMemo(
    () => ({ tasks, addTask, storageBlocked }),
    [tasks, addTask, storageBlocked],
  )

  return <TasksContext.Provider value={value}>{children}</TasksContext.Provider>
}

export function useTasks() {
  const context = React.useContext(TasksContext)
  if (!context) throw new Error("useTasks must be used within a TasksProvider")
  return context
}
