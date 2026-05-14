// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * ChatHistory Component
 *
 * Sidebar navigation showing list of past chat conversations.
 * Uses fluentui-copilot CopilotNav components for consistent Fluent design.
 */
import * as React from "react";

import { Button, Link, makeStyles, tokens, useId } from "@fluentui/react-components";
import { PanelLeftContract20Regular } from "@fluentui/react-icons";
import {
  CopilotNavCategory,
  CopilotNavCategoryItem,
  CopilotNavDrawer,
  CopilotNavDrawerBody,
  CopilotNavDrawerFooter,
  CopilotNavDrawerHeader,
  CopilotNavItem,
  CopilotNavSubItem,
  CopilotNavSubItemGroup,
} from "@fluentui-copilot/react-copilot-nav";

import { AppIcon } from "@/components/AppIcon/AppIcon";
import { ChatSubItem } from "@/components/ChatHistory/ChatSubItem";
import { config } from "@/config/constants";
import type { ChatConversation } from "@/types/chat.types";

// ============================================================================
// Styles
// ============================================================================

const useStyles = makeStyles({
  sidebarToggle: {
    position: "absolute",
    top: tokens.spacingVerticalL,
    left: tokens.spacingHorizontalL,
    zIndex: 1,
  },
  drawer: {
    minWidth: "284px",
    overflowX: "hidden",
  },
  header: {
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
    width: "100%",
    boxSizing: "border-box",
    paddingInline: 0,
    gap: tokens.spacingHorizontalXXS,
    fontWeight: tokens.fontWeightSemibold,
  },
  headerButton: {
    cursor: "pointer",
    backgroundColor: "transparent",
    border: "none",
    display: "flex",
    alignItems: "center",
    whiteSpace: "nowrap",
    gap: tokens.spacingHorizontalXXS,
    padding: `${tokens.spacingVerticalXS} 0 ${tokens.spacingVerticalXS} 0`,
    borderRadius: tokens.borderRadiusMedium,
    fontWeight: tokens.fontWeightSemibold,
    fontSize: tokens.fontSizeBase300,
    ":hover": {
      backgroundColor: tokens.colorNeutralBackground1Hover,
    },
  },
  emptyState: {
    padding: `${tokens.spacingVerticalL} ${tokens.spacingHorizontalM}`,
    fontSize: tokens.fontSizeBase200,
    textAlign: "left",
    color: tokens.colorNeutralForeground3,
  },
  drawerBody: {
    overflowX: "hidden",
  },
});

// ============================================================================
// Types
// ============================================================================

export type ChatHistoryProps = {
  /** List of chat conversations */
  conversations: ChatConversation[];
  /** Currently active conversation ID */
  activeConversationId?: string;
  /** Callback when creating a new chat */
  onNewChat: () => void;
  /** Callback when selecting a conversation */
  onSelectConversation: (conversationId: string) => void;
  /** Callback when deleting a conversation */
  onDeleteConversation?: (conversationId: string) => void;
  /** Callback when renaming a conversation */
  onRenameConversation?: (conversationId: string, newTitle: string) => void;
};

// Sidebar animation duration (matches fluentui drawer animation)
const SIDEBAR_ANIMATION_DURATION = 250;

// ============================================================================
// Main Component
// ============================================================================

export const ChatHistory = ({
  conversations,
  activeConversationId,
  onNewChat,
  onSelectConversation,
  onDeleteConversation,
  onRenameConversation,
}: ChatHistoryProps) => {
  const styles = useStyles();
  const appName = config.get("app.name");
  const id = useId("copilot-nav");

  // Drawer open state (self-managed)
  const [open, setOpen] = React.useState(false);

  // Delay showing toggle button until sidebar close animation finishes
  const [showToggleButton, setShowToggleButton] = React.useState(true);

  React.useEffect(() => {
    if (open) {
      setShowToggleButton(false);
    } else {
      const timer = setTimeout(() => {
        setShowToggleButton(true);
      }, SIDEBAR_ANIMATION_DURATION);
      return () => clearTimeout(timer);
    }
  }, [open]);

  // State to show all conversations or just recent
  const [showAllConversations, setShowAllConversations] = React.useState(false);

  const handleAppHeaderClick = () => {
    onNewChat();
    // Don't close drawer - user explicitly closes it via collapse button
  };

  const handleCollapseClick = () => {
    setOpen(false);
  };

  const handleValueChange = (_: unknown, data: { value: string }) => {
    if (data.value === "new-chat") {
      onNewChat();
      // Don't close drawer - user explicitly closes it
    } else if (data.value === "all-conversations") {
      setShowAllConversations(true);
    } else if (data.value && !data.value.startsWith("all-")) {
      onSelectConversation(data.value);
      // Don't close drawer - user explicitly closes it
    }
  };

  // Show recent or all conversations based on state
  const displayedConversations = showAllConversations ? conversations : conversations.slice(0, 5);

  return (
    <>
      <CopilotNavDrawer
        className={styles.drawer}
        open={open}
        onOpenChange={(_, { open: isOpen }) => setOpen(isOpen)}
        type="inline"
        selectedValue={activeConversationId || ""}
        selectedCategoryValue="chats"
        defaultOpenCategories={["chats"]}
        onNavItemSelect={handleValueChange}
      >
        <CopilotNavDrawerHeader style={{ paddingInlineStart: 0 }}>
          <div className={styles.header}>
            <button className={styles.headerButton} onClick={handleAppHeaderClick} type="button">
              <AppIcon showKey="sidebar.showIcon" iconKey="sidebar.icon" size={20} />
              {appName}
            </button>
            <div style={{ flex: 1 }} />
            <Button
              appearance="transparent"
              aria-label="Collapse"
              icon={<PanelLeftContract20Regular />}
              onClick={handleCollapseClick}
            />
          </div>
        </CopilotNavDrawerHeader>

        <CopilotNavDrawerBody className={styles.drawerBody}>
          {/* New Chat */}
          <CopilotNavItem icon={<AppIcon showKey="newChat.showIcon" iconKey="newChat.icon" />} value="new-chat">
            New chat
          </CopilotNavItem>

          {/* Chats Category */}
          <CopilotNavCategory value="chats">
            <CopilotNavCategoryItem id={`${id}-chats`}>Chats</CopilotNavCategoryItem>
            <CopilotNavSubItemGroup aria-labelledby={`${id}-chats`}>
              {conversations.length > 0 ? (
                <>
                  {displayedConversations
                    .filter((c) => c.id) // Filter out conversations without valid IDs
                    .map((conversation) => (
                      <ChatSubItem
                        key={conversation.id}
                        conversation={conversation}
                        onDelete={onDeleteConversation ? () => onDeleteConversation(conversation.id) : undefined}
                        onRename={
                          onRenameConversation ? (newTitle) => onRenameConversation(conversation.id, newTitle) : undefined
                        }
                      />
                    ))}
                  {conversations.length > 5 && !showAllConversations && (
                    <CopilotNavSubItem value="all-conversations" appearance="all">
                      All conversations
                    </CopilotNavSubItem>
                  )}
                </>
              ) : (
                <div className={styles.emptyState}>
                  No chat history yet.
                  <br />
                  Start a new conversation!
                </div>
              )}
            </CopilotNavSubItemGroup>
          </CopilotNavCategory>
        </CopilotNavDrawerBody>

        <CopilotNavDrawerFooter>
          <div style={{ width: "100%", textAlign: "left" }}>
            <Link
              href="https://go.microsoft.com/fwlink/?LinkId=521839"
              target="_blank"
              style={{ fontSize: tokens.fontSizeBase200 }}
            >
              Privacy Statement
            </Link>
          </div>
        </CopilotNavDrawerFooter>
      </CopilotNavDrawer>
      {showToggleButton && !open && (
        <div className={styles.sidebarToggle}>
          <Button
            appearance="transparent"
            icon={<PanelLeftContract20Regular />}
            onClick={() => setOpen(true)}
            aria-label="Open chat history"
          />
        </div>
      )}
    </>
  );
};
