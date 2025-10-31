import { Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

export const visibilityValues = ["public", "invite-only"] as const;
export type Visibility = (typeof visibilityValues)[number];

export const eventStatusValues = ["going", "interested", "declined"] as const;
export type AttendanceStatus = (typeof eventStatusValues)[number];

export interface UserDoc {
  displayName: string;
  phoneNumber?: string | null;
  email?: string | null;
  photoURL?: string | null;
  onboarded: boolean;
  theme: "system" | "light" | "dark";
  interests: string[];
  pushTokens: string[];
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

const geoSchema = z
  .object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180)
  })
  .nullable()
  .optional();

export const eventSchema = z.object({
  ownerId: z.string().min(1),
  title: z.string().min(1).max(120),
  description: z.string().max(4000).optional().nullable(),
  startAt: z.coerce.date(),
  endAt: z.coerce.date(),
  location: z.string().min(1).max(180),
  visibility: z.enum(visibilityValues),
  maxGuests: z.number().int().positive().optional().nullable(),
  geo: geoSchema,
  coverImagePath: z.string().optional().nullable()
});

export type EventCreatePayload = z.infer<typeof eventSchema>;

export const eventUpdateSchema = z
  .object({
    eventId: z.string().min(1),
    title: z.string().min(1).max(120).optional(),
    description: z.string().max(4000).optional().nullable(),
    startAt: z.coerce.date().optional(),
    endAt: z.coerce.date().optional(),
    location: z.string().min(1).max(180).optional(),
    visibility: z.enum(visibilityValues).optional(),
    maxGuests: z.number().int().positive().optional().nullable(),
    geo: geoSchema,
    coverImagePath: z.string().optional().nullable(),
    sharedInviteFriendIds: z.array(z.string().min(1)).optional()
  })
  .superRefine((value, ctx) => {
    const mutableKeys: Array<keyof typeof value> = [
      "title",
      "description",
      "startAt",
      "endAt",
      "location",
      "visibility",
      "maxGuests",
      "geo",
      "coverImagePath",
      "sharedInviteFriendIds"
    ];
    const hasUpdate = mutableKeys.some((key) => value[key] !== undefined);
    if (!hasUpdate) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "At least one field must be provided to update."
      });
    }
    if ((value.startAt && !value.endAt) || (!value.startAt && value.endAt)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "startAt and endAt must be provided together."
      });
    }
    if (value.startAt && value.endAt && value.endAt <= value.startAt) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "endAt must be after startAt."
      });
    }
  });

export type EventUpdatePayload = z.infer<typeof eventUpdateSchema>;

export const eventDeleteSchema = z.object({
  eventId: z.string().min(1),
  hardDelete: z.boolean().default(false)
});

export type EventDeletePayload = z.infer<typeof eventDeleteSchema>;

export const profileRequestSchema = z.object({
  userId: z.string().min(1)
});

export type ProfileRequestPayload = z.infer<typeof profileRequestSchema>;

export const profileUpdateSchema = z
  .object({
    userId: z.string().min(1),
    displayName: z.string().min(1).max(80).optional(),
    username: z
      .string()
      .min(3)
      .max(30)
      .regex(/^[A-Za-z0-9._-]+$/, "Usernames may contain letters, numbers, dots, underscores, and hyphens.")
      .optional(),
    bio: z.string().max(200).optional().nullable(),
    phoneNumber: z.string().regex(/^\+[1-9]\d{1,14}$/, "Phone number must be in E.164 format (e.g., +12345678901)").optional().nullable(),
    primaryLocation: geoSchema,
    photoURL: z.string().url().optional().nullable()
  })
  .superRefine((value, ctx) => {
    const mutableKeys: Array<keyof typeof value> = ["displayName", "username", "bio", "phoneNumber", "primaryLocation", "photoURL"];
    const hasUpdate = mutableKeys.some((key) => value[key] !== undefined);
    if (!hasUpdate) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "At least one field must be provided to update."
      });
    }
  });

export type ProfileUpdatePayload = z.infer<typeof profileUpdateSchema>;

export const profileAttendedSchema = z.object({
  userId: z.string().min(1),
  limit: z.number().int().positive().max(50).default(25)
});

export type ProfileAttendedPayload = z.infer<typeof profileAttendedSchema>;

export interface EventDoc {
  ownerId: string;
  title: string;
  description?: string | null;
  startAt: Timestamp;
  endAt: Timestamp;
  location: string;
  visibility: Visibility;
  maxGuests?: number | null;
  geo?: {
    lat: number;
    lng: number;
  } | null;
  coverImagePath?: string | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  canceled: boolean;
}

export const rsvpSchema = z.object({
  status: z.enum(eventStatusValues).default("going"),
  arrivalAt: z.string().datetime({ offset: true }).optional().nullable()
});

export type RSVPRequest = z.infer<typeof rsvpSchema>;

export const rsvpRequestSchema = z
  .object({
    eventId: z.string().min(1),
    status: z.enum(eventStatusValues).default("going"),
    arrivalAt: z.string().datetime({ offset: true }).optional().nullable(),
    userId: z.string().optional(),
    eventIdVariants: z.array(z.string().min(1)).optional()
  })
  .transform((value) => ({
    ...value,
    status: value.status ?? "going",
    eventIdVariants: value.eventIdVariants ?? []
  }));

export type RSVPCallPayload = z.infer<typeof rsvpRequestSchema>;

export interface EventMemberDoc {
  userId: string;
  status: AttendanceStatus;
  arrivalAt?: Timestamp | null;
  role: "host" | "attendee" | "admin";
  updatedAt: Timestamp;
}

export const feedQuerySchema = z
  .object({
    userId: z.string(),
    limit: z.number().int().positive().max(50).default(20),
    startAfter: z.string().optional(),
    visibility: z.enum(visibilityValues).optional(),
    from: z.string().datetime({ offset: true }).optional(),
    to: z.string().datetime({ offset: true }).optional()
  })
  .transform((value) => ({
    ...value,
    limit: value.limit ?? 20
  }));

export type FeedQuery = z.infer<typeof feedQuerySchema>;

export interface InviteDoc {
  eventId: string;
  senderId: string;
  recipientPhone: string;
  recipientUserId?: string | null;
  status: "sent" | "accepted" | "declined";
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface WidgetSnapshotDoc {
  userId: string;
  generatedAt: Timestamp;
  entries: Array<{
    eventId: string;
    title: string;
    location: string;
    startAt: Timestamp;
    coverImageURL?: string | null;
  }>;
}

// Social APIs
export const shareEventSchema = z.object({
  senderId: z.string().min(1),
  eventId: z.string().min(1),
  recipientIds: z.array(z.string().min(1)).min(1)
});

export type ShareEventPayload = z.infer<typeof shareEventSchema>;

export const friendInviteSchema = z.object({
  senderId: z.string().min(1),
  recipientPhone: z.string().optional(),
  recipientEmail: z.string().email().optional()
}).refine((data) => data.recipientPhone || data.recipientEmail, {
  message: "Either recipientPhone or recipientEmail must be provided"
});

export type FriendInvitePayload = z.infer<typeof friendInviteSchema>;

export const sendFriendRequestSchema = z.object({
  recipientUserId: z.string().min(1)
});

export type SendFriendRequestPayload = z.infer<typeof sendFriendRequestSchema>;

export const respondToFriendRequestSchema = z.object({
  inviteId: z.string().min(1),
  accept: z.boolean()
});

export type RespondToFriendRequestPayload = z.infer<typeof respondToFriendRequestSchema>;

export const listFriendsSchema = z.object({
  userId: z.string().min(1),
  includeInvites: z.boolean().default(true)
});

export type ListFriendsPayload = z.infer<typeof listFriendsSchema>;

export interface FriendDoc {
  userId: string;
  friendId: string;
  status: "active" | "blocked";
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface FriendInviteDoc {
  senderId: string;
  recipientPhone?: string | null;
  recipientEmail?: string | null;
  recipientUserId?: string | null;
  status: "pending" | "accepted" | "declined";
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

// Chat schemas
export const sendMessageSchema = z.object({
  chatId: z.string().min(1),
  text: z.string().min(1).max(2000)
});

export type SendMessagePayload = z.infer<typeof sendMessageSchema>;

export const getMessagesSchema = z.object({
  chatId: z.string().min(1),
  limit: z.number().int().positive().optional(),
  before: z.coerce.date().optional()
}).transform((value) => ({
  ...value,
  limit: value.limit ?? 50
}));

export type GetMessagesPayload = z.infer<typeof getMessagesSchema>;

export interface ChatDoc {
  chatId: string;
  eventId: string;
  eventTitle: string;
  participantIds: string[];
  createdAt: Timestamp;
  lastMessageAt: Timestamp | null;
  lastMessageText: string | null;
  lastMessageSenderId: string | null;
  lastMessageSenderName: string | null;
  unreadCounts: Record<string, number>;
  archived?: boolean;
}

export interface MessageDoc {
  messageId: string;
  senderId: string;
  senderName: string;
  senderPhotoURL?: string | null;
  text: string;
  createdAt: Timestamp;
  type: "text" | "system";
}
