CREATE TYPE public.app_role        AS ENUM ('super_admin','business_owner','dispatcher','rider');
CREATE TYPE public.business_role   AS ENUM ('owner','manager','staff');
CREATE TYPE public.rider_status    AS ENUM ('offline','available','on_delivery','paused');
CREATE TYPE public.order_status    AS ENUM ('draft','pending_assignment','offered','assigned','picked_up','delivered','cancelled');
CREATE TYPE public.offer_response  AS ENUM ('pending','accepted','declined','expired');
