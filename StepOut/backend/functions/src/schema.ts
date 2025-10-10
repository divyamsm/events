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
