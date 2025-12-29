-- Phase 5: Tasks Migration
-- Creates tasks, task_comments, task_attachments, task_dependencies, task_activities, and task_notifications tables

-- =====================================================
-- Table: tasks
-- =====================================================
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    created_by TEXT NOT NULL,

    -- Basic Information
    title TEXT NOT NULL,
    description TEXT,
    type TEXT DEFAULT 'general', -- general, session, workflow

    -- Status & Priority
    status TEXT DEFAULT 'todo', -- todo, in_progress, on_hold, completed, cancelled
    priority TEXT DEFAULT 'medium', -- low, medium, high, urgent

    -- Assignment & Collaboration
    assigned_to JSONB DEFAULT '[]', -- Array of user IDs
    watchers JSONB DEFAULT '[]', -- Array of user IDs watching this task

    -- Dates & Timeline
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    due_date TIMESTAMPTZ,
    start_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    completed_by TEXT,

    -- Estimation & Tracking
    estimated_hours NUMERIC DEFAULT 0,
    "order" INTEGER DEFAULT 0, -- For drag-and-drop ordering within status

    -- Subtasks (stored as JSONB array)
    subtasks JSONB DEFAULT '[]', -- [{id, title, completed, completed_at, completed_by}]

    -- Comments & Activity
    comment_count INTEGER DEFAULT 0,
    time_entry_ids JSONB DEFAULT '[]', -- Linked time tracking entries

    -- Workflow Integration (optional - only if type === "workflow")
    workflow_id TEXT,
    workflow_step_id TEXT,
    workflow_name TEXT,
    workflow_step_name TEXT,
    auto_created BOOLEAN DEFAULT false,
    sync_with_workflow BOOLEAN DEFAULT false,

    -- Session Integration (optional - only if type === "session")
    session_id TEXT,
    session_name TEXT,
    session_date TIMESTAMPTZ,

    CONSTRAINT fk_organization FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- Indexes for tasks table
CREATE INDEX IF NOT EXISTS idx_tasks_organization ON tasks(organization_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_created_by ON tasks(created_by);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to ON tasks USING GIN (assigned_to);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON tasks(updated_at);
CREATE INDEX IF NOT EXISTS idx_tasks_workflow ON tasks(workflow_id) WHERE workflow_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_session ON tasks(session_id) WHERE session_id IS NOT NULL;

-- =====================================================
-- Table: task_comments
-- =====================================================
CREATE TABLE IF NOT EXISTS task_comments (
    id TEXT PRIMARY KEY NOT NULL,
    task_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    text TEXT NOT NULL,
    mentions JSONB DEFAULT '[]', -- [{userId, userName}]
    attachments JSONB DEFAULT '[]', -- [{fileName, fileUrl, fileType, fileSize}]
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_task FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

-- Indexes for task_comments table
CREATE INDEX IF NOT EXISTS idx_task_comments_task ON task_comments(task_id);
CREATE INDEX IF NOT EXISTS idx_task_comments_user ON task_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_task_comments_created ON task_comments(created_at);

-- =====================================================
-- Table: task_attachments
-- =====================================================
CREATE TABLE IF NOT EXISTS task_attachments (
    id TEXT PRIMARY KEY NOT NULL,
    task_id TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    file_url TEXT NOT NULL,
    uploaded_by TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_task_attachment FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

-- Indexes for task_attachments table
CREATE INDEX IF NOT EXISTS idx_task_attachments_task ON task_attachments(task_id);

-- =====================================================
-- Table: task_dependencies
-- =====================================================
CREATE TABLE IF NOT EXISTS task_dependencies (
    id TEXT PRIMARY KEY NOT NULL,
    task_id TEXT NOT NULL,
    depends_on_task_id TEXT NOT NULL,
    dependency_type TEXT DEFAULT 'blocks', -- blocks, related
    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_task_dep FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_depends_on_task FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

-- Indexes for task_dependencies table
CREATE INDEX IF NOT EXISTS idx_task_dependencies_task ON task_dependencies(task_id);
CREATE INDEX IF NOT EXISTS idx_task_dependencies_depends ON task_dependencies(depends_on_task_id);

-- =====================================================
-- Table: task_activities
-- =====================================================
CREATE TABLE IF NOT EXISTS task_activities (
    id TEXT PRIMARY KEY NOT NULL,
    task_id TEXT NOT NULL,
    type TEXT NOT NULL, -- TASK_CREATED, TASK_UPDATED, STATUS_CHANGED, etc.
    user_id TEXT NOT NULL,
    organization_id TEXT NOT NULL,
    data JSONB DEFAULT '{}', -- Activity-specific data
    timestamp TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_task_activity FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

-- Indexes for task_activities table
CREATE INDEX IF NOT EXISTS idx_task_activities_task ON task_activities(task_id);
CREATE INDEX IF NOT EXISTS idx_task_activities_timestamp ON task_activities(timestamp);
CREATE INDEX IF NOT EXISTS idx_task_activities_org ON task_activities(organization_id);

-- =====================================================
-- Table: task_notifications
-- =====================================================
CREATE TABLE IF NOT EXISTS task_notifications (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    task_id TEXT,
    type TEXT NOT NULL, -- TASK_ASSIGNED, MENTION, etc.
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}',

    CONSTRAINT fk_task_notification FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

-- Indexes for task_notifications table
CREATE INDEX IF NOT EXISTS idx_task_notifications_user ON task_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_task_notifications_read ON task_notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_task_notifications_created ON task_notifications(created_at);
CREATE INDEX IF NOT EXISTS idx_task_notifications_task ON task_notifications(task_id) WHERE task_id IS NOT NULL;

-- =====================================================
-- Triggers for updated_at
-- =====================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to tasks
DROP TRIGGER IF EXISTS update_tasks_updated_at ON tasks;
CREATE TRIGGER update_tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Apply trigger to task_comments
DROP TRIGGER IF EXISTS update_task_comments_updated_at ON task_comments;
CREATE TRIGGER update_task_comments_updated_at
    BEFORE UPDATE ON task_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- Row Level Security (RLS)
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies for tasks
CREATE POLICY "Users can view tasks in their organization" ON tasks
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can insert tasks in their organization" ON tasks
    FOR INSERT WITH CHECK (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can update tasks in their organization" ON tasks
    FOR UPDATE USING (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can delete tasks they created" ON tasks
    FOR DELETE USING (
        created_by = auth.uid()::text
    );

-- RLS Policies for task_comments
CREATE POLICY "Users can view comments on tasks in their organization" ON task_comments
    FOR SELECT USING (
        task_id IN (
            SELECT id FROM tasks WHERE organization_id IN (
                SELECT organization_id FROM users WHERE id = auth.uid()::text
            )
        )
    );

CREATE POLICY "Users can insert comments on tasks in their organization" ON task_comments
    FOR INSERT WITH CHECK (
        task_id IN (
            SELECT id FROM tasks WHERE organization_id IN (
                SELECT organization_id FROM users WHERE id = auth.uid()::text
            )
        )
    );

CREATE POLICY "Users can update their own comments" ON task_comments
    FOR UPDATE USING (user_id = auth.uid()::text);

CREATE POLICY "Users can delete their own comments" ON task_comments
    FOR DELETE USING (user_id = auth.uid()::text);

-- RLS Policies for task_attachments, task_dependencies, task_activities, task_notifications
-- (Similar pattern - users can access based on task ownership/organization)

CREATE POLICY "Users can view attachments on tasks in their organization" ON task_attachments
    FOR SELECT USING (
        task_id IN (
            SELECT id FROM tasks WHERE organization_id IN (
                SELECT organization_id FROM users WHERE id = auth.uid()::text
            )
        )
    );

CREATE POLICY "Users can view activities on tasks in their organization" ON task_activities
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can view their own notifications" ON task_notifications
    FOR SELECT USING (user_id = auth.uid()::text);

CREATE POLICY "Users can update their own notifications" ON task_notifications
    FOR UPDATE USING (user_id = auth.uid()::text);
