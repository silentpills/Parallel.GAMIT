--
-- PostgreSQL database dump
--

-- Dumped from database version 15.13 (Debian 15.13-0+deb12u1)
-- Dumped by pg_dump version 15.13 (Debian 15.13-0+deb12u1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: delete_rows_referencing_stations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_rows_referencing_stations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
	    deleted_visit_id INTEGER;
    BEGIN
    	    -- delete related rows from api tables
        DELETE FROM api_stationmetagaps WHERE station_meta_id IN (SELECT id FROM api_stationmeta WHERE station_id = OLD.api_id);
	    DELETE FROM api_stationmeta WHERE station_id = OLD.api_id; 
	    DELETE FROM api_rolepersonstation WHERE station_id = OLD.api_id;
	    DELETE FROM api_stationimages WHERE station_id = OLD.api_id;
	    DELETE FROM api_stationattachedfiles WHERE station_id = OLD.api_id;
	    
	    -- delete visits and other related rows (also from api tables)
	    DELETE FROM api_visits WHERE station_id = OLD.api_id RETURNING id INTO deleted_visit_id;
	    DELETE FROM api_visitimages WHERE visit_id = deleted_visit_id;
	    DELETE FROM api_visitattachedfiles WHERE visit_id = deleted_visit_id;
	    DELETE FROM api_visitgnssdatafiles WHERE visit_id = deleted_visit_id;
	    DELETE FROM api_visits_people WHERE visits_id = deleted_visit_id;
	    
	    -- delete from stationinfo
	    DELETE FROM stationinfo WHERE "NetworkCode" = OLD."NetworkCode" and "StationCode" = OLD."StationCode";
	    
	    -- rinex rows must not be deleted
	    
	    RETURN OLD;
    END;
    $$;


--
-- Name: ecef2neu(numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ecef2neu(dx numeric, dy numeric, dz numeric, lat numeric, lon numeric) RETURNS double precision[]
    LANGUAGE sql
    AS $_$
select 
array[-sin(radians($4))*cos(radians($5))*$1 - sin(radians($4))*sin(radians($5))*$2 + cos(radians($4))*$3::numeric,
      -sin(radians($5))*$1 + cos(radians($5))*$2::numeric,
      cos(radians($4))*cos(radians($5))*$1 + cos(radians($4))*sin(radians($5))*$2 + sin(radians($4))*$3::numeric];

$_$;


--
-- Name: fyear(numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fyear("Year" numeric, "DOY" numeric, "Hour" numeric DEFAULT 12, "Minute" numeric DEFAULT 0, "Second" numeric DEFAULT 0) RETURNS numeric
    LANGUAGE sql
    AS $_$
SELECT CASE 
WHEN isleapyear(cast($1 as integer)) = True  THEN $1 + ($2 + $3/24 + $4/1440 + $5/86400)/366
WHEN isleapyear(cast($1 as integer)) = False THEN $1 + ($2 + $3/24 + $4/1440 + $5/86400)/365
END;

$_$;


--
-- Name: horizdist(double precision[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.horizdist(neu double precision[]) RETURNS double precision
    LANGUAGE sql
    AS $_$

select 
sqrt(($1)[1]^2 + ($1)[2]^2 + ($1)[3]^2)

$_$;


--
-- Name: isleapyear(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isleapyear(year integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1 % 4 = 0) AND (($1 % 100 <> 0) or ($1 % 400 = 0))
$_$;


--
-- Name: stationalias_check(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stationalias_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
	stnalias BOOLEAN;
BEGIN
SELECT (SELECT "StationCode" FROM stations WHERE "StationCode" = new."StationAlias") IS NULL INTO stnalias;
IF stnalias THEN
    RETURN NEW;
ELSE
	RAISE EXCEPTION 'Invalid station alias: already exists as a station code';
END IF;
END
$$;


--
-- Name: update_has_gaps_update_needed_field(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_has_gaps_update_needed_field() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE api_stationmeta 
            SET has_gaps_update_needed = true 
            WHERE station_id = (
            SELECT api_id 
            FROM stations s 
            WHERE s."NetworkCode" = OLD."NetworkCode" and s."StationCode" = OLD."StationCode" 
            );
            RETURN OLD;
        ELSE
            UPDATE api_stationmeta 
            SET has_gaps_update_needed = true 
            WHERE station_id = (
            SELECT api_id 
            FROM stations s 
            WHERE s."NetworkCode" = NEW."NetworkCode" and s."StationCode" = NEW."StationCode" 
            );
            RETURN NEW;
        END IF;
    END;
    $$;


--
-- Name: update_has_stationinfo_field(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_has_stationinfo_field() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE api_stationmeta 
            SET has_stationinfo = EXISTS (SELECT 1 FROM stationinfo si where si."NetworkCode" = OLD."NetworkCode" and si."StationCode" = OLD."StationCode" )
            WHERE station_id = (
            SELECT api_id 
            FROM stations s 
            WHERE s."NetworkCode" = OLD."NetworkCode" and s."StationCode" = OLD."StationCode" 
            );
            RETURN OLD;
        ELSE
            UPDATE api_stationmeta 
            SET has_stationinfo = true 
            WHERE station_id = (
            SELECT api_id 
            FROM stations s 
            WHERE s."NetworkCode" = NEW."NetworkCode" and s."StationCode" = NEW."StationCode" 
            );
            RETURN NEW;
        END IF;
    END;
    $$;


--
-- Name: update_station_timespan(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_station_timespan("NetworkCode" character varying, "StationCode" character varying) RETURNS void
    LANGUAGE sql
    AS $_$
update stations set 
"DateStart" = 
    (SELECT MIN("ObservationFYear") as MINN 
     FROM rinex WHERE "NetworkCode" = $1 AND
     "StationCode" = $2),
"DateEnd" = 
    (SELECT MAX("ObservationFYear") as MAXX 
     FROM rinex WHERE "NetworkCode" = $1 AND
     "StationCode" = $2)
WHERE "NetworkCode" = $1 AND "StationCode" = $2
$_$;


--
-- Name: update_timespan_trigg(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_timespan_trigg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    update stations set 
"DateStart" = 
    (SELECT MIN("ObservationFYear") as MINN 
     FROM rinex 
     WHERE "NetworkCode" = new."NetworkCode" AND
           "StationCode" = new."StationCode"),
"DateEnd" = 
    (SELECT MAX("ObservationFYear") as MAXX 
     FROM rinex 
     WHERE "NetworkCode" = new."NetworkCode" AND
           "StationCode" = new."StationCode")
WHERE "NetworkCode" = new."NetworkCode" 
  AND "StationCode" = new."StationCode";

           RETURN new;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: antennas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.antennas (
    "AntennaCode" character varying(22) NOT NULL,
    "AntennaDescription" character varying,
    api_id integer NOT NULL
);


--
-- Name: antennas_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.antennas_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: antennas_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.antennas_api_id_seq OWNED BY public.antennas.api_id;


--
-- Name: api_campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_campaigns (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL
);


--
-- Name: api_campaigns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_campaigns ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_campaigns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_clustertype; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_clustertype (
    id bigint NOT NULL,
    name character varying(100) NOT NULL
);


--
-- Name: api_clustertype_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_clustertype ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_clustertype_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_country; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_country (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    two_digits_code character varying(2) NOT NULL,
    three_digits_code character varying(3) NOT NULL
);


--
-- Name: api_country_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_country ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_endpoint; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_endpoint (
    id bigint NOT NULL,
    path character varying(100) NOT NULL,
    description character varying(100) NOT NULL,
    method character varying(6) NOT NULL
);


--
-- Name: api_endpoint_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_endpoint ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_endpoint_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_endpointscluster; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_endpointscluster (
    id bigint NOT NULL,
    description character varying(100) NOT NULL,
    role_type character varying(15) NOT NULL,
    cluster_type_id bigint NOT NULL,
    resource_id bigint NOT NULL
);


--
-- Name: api_endpointscluster_endpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_endpointscluster_endpoints (
    id bigint NOT NULL,
    endpointscluster_id bigint NOT NULL,
    endpoint_id bigint NOT NULL
);


--
-- Name: api_endpointscluster_endpoints_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_endpointscluster_endpoints ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_endpointscluster_endpoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_endpointscluster_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_endpointscluster ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_endpointscluster_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_monumenttype; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_monumenttype (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    photo_path character varying(100) NOT NULL
);


--
-- Name: api_monumenttype_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_monumenttype ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_monumenttype_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_person; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_person (
    id bigint NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    phone character varying(15) NOT NULL,
    address character varying(100) NOT NULL,
    photo character varying(100) NOT NULL,
    user_id bigint
);


--
-- Name: api_person_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_person ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_person_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_resource; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_resource (
    id bigint NOT NULL,
    name character varying(100) NOT NULL
);


--
-- Name: api_resource_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_resource ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_resource_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_role (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    role_api boolean NOT NULL,
    allow_all boolean NOT NULL,
    is_active boolean NOT NULL
);


--
-- Name: api_role_endpoints_clusters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_role_endpoints_clusters (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    endpointscluster_id bigint NOT NULL
);


--
-- Name: api_role_endpoints_clusters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_role_endpoints_clusters ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_role_endpoints_clusters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_role ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_rolepersonstation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_rolepersonstation (
    id bigint NOT NULL,
    person_id bigint NOT NULL,
    station_id integer NOT NULL,
    role_id bigint NOT NULL
);


--
-- Name: api_rolepersonstation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_rolepersonstation ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_rolepersonstation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_stationattachedfiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_stationattachedfiles (
    id bigint NOT NULL,
    file character varying(100) NOT NULL,
    filename character varying(255) NOT NULL,
    description character varying(500) NOT NULL,
    station_id integer NOT NULL
);


--
-- Name: api_stationattachedfiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_stationattachedfiles ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_stationattachedfiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_stationimages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_stationimages (
    id bigint NOT NULL,
    image character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(500) NOT NULL,
    station_id integer NOT NULL
);


--
-- Name: api_stationimages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_stationimages ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_stationimages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_stationmeta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_stationmeta (
    id bigint NOT NULL,
    remote_access_link character varying(500) NOT NULL,
    has_battery boolean NOT NULL,
    battery_description character varying(100) NOT NULL,
    has_communications boolean NOT NULL,
    communications_description character varying(100) NOT NULL,
    comments character varying NOT NULL,
    navigation_file character varying(100) NOT NULL,
    navigation_filename character varying(255) NOT NULL,
    has_gaps boolean NOT NULL,
    has_gaps_last_update_datetime timestamp with time zone,
    has_gaps_update_needed boolean NOT NULL,
    has_stationinfo boolean NOT NULL,
    monument_type_id bigint,
    station_id integer NOT NULL,
    status_id bigint,
    station_type_id bigint
);


--
-- Name: api_stationmeta_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_stationmeta ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_stationmeta_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_stationmetagaps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_stationmetagaps (
    id bigint NOT NULL,
    rinex_count integer NOT NULL,
    record_start_date_start timestamp with time zone,
    record_start_date_end timestamp with time zone,
    record_end_date_start timestamp with time zone,
    record_end_date_end timestamp with time zone,
    station_meta_id bigint NOT NULL
);


--
-- Name: api_stationmetagaps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_stationmetagaps ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_stationmetagaps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_stationrole; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_stationrole (
    id bigint NOT NULL,
    name character varying(100) NOT NULL
);


--
-- Name: api_stationrole_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_stationrole ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_stationrole_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_stationstatus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_stationstatus (
    id bigint NOT NULL,
    name character varying(100) NOT NULL
);


--
-- Name: api_stationstatus_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_stationstatus ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_stationstatus_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_stationtype; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_stationtype (
    id bigint NOT NULL,
    name character varying(100) NOT NULL
);


--
-- Name: api_stationtype_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_stationtype ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_stationtype_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_user (
    id bigint NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL,
    phone character varying(15) NOT NULL,
    address character varying(100) NOT NULL,
    photo character varying(100) NOT NULL,
    role_id bigint NOT NULL
);


--
-- Name: api_user_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_user_groups (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    group_id integer NOT NULL
);


--
-- Name: api_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_user_groups ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_user ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_user_user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_user_user_permissions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: api_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_user_user_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_user_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_visitattachedfiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_visitattachedfiles (
    id bigint NOT NULL,
    file character varying(100) NOT NULL,
    filename character varying(255) NOT NULL,
    description character varying(500) NOT NULL,
    visit_id bigint NOT NULL
);


--
-- Name: api_visitattachedfiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_visitattachedfiles ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_visitattachedfiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_visitgnssdatafiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_visitgnssdatafiles (
    id bigint NOT NULL,
    file character varying(100) NOT NULL,
    filename character varying(255) NOT NULL,
    description character varying(500) NOT NULL,
    visit_id bigint NOT NULL
);


--
-- Name: api_visitgnssdatafiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_visitgnssdatafiles ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_visitgnssdatafiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_visitimages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_visitimages (
    id bigint NOT NULL,
    image character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(500) NOT NULL,
    visit_id bigint NOT NULL
);


--
-- Name: api_visitimages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_visitimages ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_visitimages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_visits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_visits (
    id bigint NOT NULL,
    date date NOT NULL,
    log_sheet_file character varying(100),
    log_sheet_filename character varying(255) NOT NULL,
    navigation_file character varying(100) NOT NULL,
    navigation_filename character varying(255) NOT NULL,
    campaign_id bigint,
    station_id integer NOT NULL,
    comments character varying NOT NULL
);


--
-- Name: api_visits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_visits ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_visits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: api_visits_people; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_visits_people (
    id bigint NOT NULL,
    visits_id bigint NOT NULL,
    person_id bigint NOT NULL
);


--
-- Name: api_visits_people_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.api_visits_people ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_visits_people_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: apr_coords; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apr_coords (
    "NetworkCode" character varying NOT NULL,
    "StationCode" character varying NOT NULL,
    "FYear" numeric,
    x numeric,
    y numeric,
    z numeric,
    sn numeric,
    se numeric,
    su numeric,
    "ReferenceFrame" character varying(20),
    "Year" integer NOT NULL,
    "DOY" integer NOT NULL,
    api_id integer NOT NULL
);


--
-- Name: apr_coords_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.apr_coords_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: apr_coords_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.apr_coords_api_id_seq OWNED BY public.apr_coords.api_id;


--
-- Name: auditlog_logentry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditlog_logentry (
    id integer NOT NULL,
    object_pk character varying(255) NOT NULL,
    object_id bigint,
    object_repr text NOT NULL,
    action smallint NOT NULL,
    changes jsonb,
    "timestamp" timestamp with time zone NOT NULL,
    actor_id bigint,
    content_type_id integer NOT NULL,
    remote_addr inet,
    additional_data jsonb,
    serialized_data jsonb,
    cid character varying(255),
    changes_text text NOT NULL,
    CONSTRAINT auditlog_logentry_action_check CHECK ((action >= 0))
);


--
-- Name: auditlog_logentry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditlog_logentry ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditlog_logentry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auth_group ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_group_permissions (
    id bigint NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auth_group_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auth_permission ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aws_sync; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aws_sync (
    "NetworkCode" character varying NOT NULL,
    "StationCode" character varying NOT NULL,
    "StationAlias" character varying(4) NOT NULL,
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    sync_date timestamp without time zone,
    api_id integer NOT NULL
);


--
-- Name: aws_sync_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.aws_sync_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: aws_sync_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.aws_sync_api_id_seq OWNED BY public.aws_sync.api_id;


--
-- Name: data_source; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    try_order numeric NOT NULL,
    protocol character varying NOT NULL,
    fqdn character varying NOT NULL,
    username character varying,
    password character varying,
    path character varying,
    format character varying,
    api_id integer NOT NULL
);


--
-- Name: data_source_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.data_source_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_source_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.data_source_api_id_seq OWNED BY public.data_source.api_id;


--
-- Name: django_admin_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_admin_log (
    id integer NOT NULL,
    action_time timestamp with time zone NOT NULL,
    object_id text,
    object_repr character varying(200) NOT NULL,
    action_flag smallint NOT NULL,
    change_message text NOT NULL,
    content_type_id integer,
    user_id bigint NOT NULL,
    CONSTRAINT django_admin_log_action_flag_check CHECK ((action_flag >= 0))
);


--
-- Name: django_admin_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.django_admin_log ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_admin_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.django_content_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_migrations (
    id bigint NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.django_migrations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


--
-- Name: earthquakes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.earthquakes (
    date timestamp without time zone NOT NULL,
    lat numeric NOT NULL,
    lon numeric NOT NULL,
    depth numeric,
    mag numeric,
    strike1 numeric,
    dip1 numeric,
    rake1 numeric,
    strike2 numeric,
    dip2 numeric,
    rake2 numeric,
    id character varying(40),
    location character varying(120),
    api_id integer NOT NULL
);


--
-- Name: earthquakes_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.earthquakes_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: earthquakes_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.earthquakes_api_id_seq OWNED BY public.earthquakes.api_id;


--
-- Name: etm_params_uid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.etm_params_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: etm_params; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.etm_params (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    soln character varying(10) NOT NULL,
    object character varying(10) NOT NULL,
    terms numeric,
    frequencies numeric[],
    jump_type numeric,
    relaxation numeric[],
    "Year" numeric,
    "DOY" numeric,
    action character varying(1),
    uid integer DEFAULT nextval('public.etm_params_uid_seq'::regclass) NOT NULL
);


--
-- Name: etmsv2_uid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.etmsv2_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: etms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.etms (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    soln character varying(10) NOT NULL,
    object character varying(10) NOT NULL,
    t_ref numeric,
    jump_type numeric,
    relaxation numeric[],
    frequencies numeric[],
    params numeric[],
    sigmas numeric[],
    metadata text,
    hash numeric,
    jump_date timestamp without time zone,
    uid integer DEFAULT nextval('public.etmsv2_uid_seq'::regclass) NOT NULL,
    stack character varying(20)
);


--
-- Name: events_event_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    event_id bigint DEFAULT nextval('public.events_event_id_seq'::regclass) NOT NULL,
    "EventDate" timestamp without time zone DEFAULT now() NOT NULL,
    "EventType" character varying(6),
    "NetworkCode" character varying(3),
    "StationCode" character varying(4),
    "Year" integer,
    "DOY" integer,
    "Description" text,
    stack text,
    module text,
    node text
);


--
-- Name: executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.executions (
    id integer DEFAULT nextval('public.executions_id_seq'::regclass) NOT NULL,
    script character varying(40),
    exec_date timestamp without time zone DEFAULT now(),
    api_id integer NOT NULL
);


--
-- Name: executions_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.executions_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: executions_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.executions_api_id_seq OWNED BY public.executions.api_id;


--
-- Name: gamit_htc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gamit_htc (
    "AntennaCode" character varying(22) NOT NULL,
    "HeightCode" character varying(5) NOT NULL,
    v_offset numeric,
    h_offset numeric,
    api_id integer NOT NULL
);


--
-- Name: gamit_htc_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gamit_htc_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gamit_htc_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gamit_htc_api_id_seq OWNED BY public.gamit_htc.api_id;


--
-- Name: gamit_soln; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gamit_soln (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "Project" character varying(20) NOT NULL,
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    "FYear" numeric,
    "X" numeric,
    "Y" numeric,
    "Z" numeric,
    sigmax numeric,
    sigmay numeric,
    sigmaz numeric,
    "VarianceFactor" numeric,
    sigmaxy numeric,
    sigmayz numeric,
    sigmaxz numeric,
    api_id integer NOT NULL
);


--
-- Name: gamit_soln_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gamit_soln_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gamit_soln_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gamit_soln_api_id_seq OWNED BY public.gamit_soln.api_id;


--
-- Name: gamit_soln_excl; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gamit_soln_excl (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "Project" character varying(20) NOT NULL,
    "Year" bigint NOT NULL,
    "DOY" bigint NOT NULL,
    residual numeric,
    api_id integer NOT NULL
);


--
-- Name: gamit_soln_excl_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gamit_soln_excl_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gamit_soln_excl_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gamit_soln_excl_api_id_seq OWNED BY public.gamit_soln_excl.api_id;


--
-- Name: gamit_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gamit_stats (
    "Project" character varying(20) NOT NULL,
    subnet numeric NOT NULL,
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    "FYear" numeric,
    wl numeric,
    nl numeric,
    nrms numeric,
    relaxed_constrains text,
    max_overconstrained character varying(8),
    updated_apr text,
    iterations numeric,
    node character varying(50),
    execution_time numeric,
    execution_date timestamp without time zone,
    system character(1) NOT NULL,
    api_id integer NOT NULL
);


--
-- Name: gamit_stats_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gamit_stats_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gamit_stats_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gamit_stats_api_id_seq OWNED BY public.gamit_stats.api_id;


--
-- Name: gamit_subnets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gamit_subnets (
    "Project" character varying(20) NOT NULL,
    subnet numeric NOT NULL,
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    centroid numeric[],
    stations character varying[],
    alias character varying[],
    ties character varying[],
    api_id integer NOT NULL
);


--
-- Name: gamit_subnets_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gamit_subnets_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gamit_subnets_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gamit_subnets_api_id_seq OWNED BY public.gamit_subnets.api_id;


--
-- Name: gamit_ztd; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gamit_ztd (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "Date" timestamp without time zone NOT NULL,
    "Project" character varying(20) NOT NULL,
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    "ZTD" numeric NOT NULL,
    model numeric,
    sigma numeric,
    api_id integer NOT NULL
);


--
-- Name: gamit_ztd_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gamit_ztd_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gamit_ztd_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gamit_ztd_api_id_seq OWNED BY public.gamit_ztd.api_id;


--
-- Name: keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.keys (
    "KeyCode" character varying(7) NOT NULL,
    "TotalChars" integer,
    rinex_col_out character varying,
    rinex_col_in character varying(60),
    isnumeric bit(1),
    api_id integer NOT NULL
);


--
-- Name: keys_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.keys_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: keys_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.keys_api_id_seq OWNED BY public.keys.api_id;


--
-- Name: locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.locks (
    filename text NOT NULL,
    "NetworkCode" character varying(3),
    "StationCode" character varying(4),
    api_id integer NOT NULL
);


--
-- Name: locks_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.locks_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locks_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.locks_api_id_seq OWNED BY public.locks.api_id;


--
-- Name: networks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.networks (
    "NetworkCode" character varying NOT NULL,
    "NetworkName" character varying,
    api_id integer NOT NULL
);


--
-- Name: networks_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.networks_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: networks_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.networks_api_id_seq OWNED BY public.networks.api_id;


--
-- Name: ppp_soln; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ppp_soln (
    "NetworkCode" character varying NOT NULL,
    "StationCode" character varying NOT NULL,
    "X" numeric(12,4),
    "Y" numeric(12,4),
    "Z" numeric(12,4),
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    "ReferenceFrame" character varying(20) NOT NULL,
    sigmax numeric,
    sigmay numeric,
    sigmaz numeric,
    sigmaxy numeric,
    sigmaxz numeric,
    sigmayz numeric,
    hash integer,
    api_id integer NOT NULL
);


--
-- Name: ppp_soln_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ppp_soln_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ppp_soln_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ppp_soln_api_id_seq OWNED BY public.ppp_soln.api_id;


--
-- Name: ppp_soln_excl; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ppp_soln_excl (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    api_id integer NOT NULL
);


--
-- Name: ppp_soln_excl_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ppp_soln_excl_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ppp_soln_excl_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ppp_soln_excl_api_id_seq OWNED BY public.ppp_soln_excl.api_id;


--
-- Name: receivers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receivers (
    "ReceiverCode" character varying(22) NOT NULL,
    "ReceiverDescription" character varying(22),
    api_id integer NOT NULL
);


--
-- Name: receivers_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.receivers_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: receivers_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.receivers_api_id_seq OWNED BY public.receivers.api_id;


--
-- Name: rinex; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rinex (
    "NetworkCode" character varying NOT NULL,
    "StationCode" character varying NOT NULL,
    "ObservationYear" numeric NOT NULL,
    "ObservationMonth" numeric NOT NULL,
    "ObservationDay" numeric NOT NULL,
    "ObservationDOY" numeric NOT NULL,
    "ObservationFYear" numeric NOT NULL,
    "ObservationSTime" timestamp without time zone,
    "ObservationETime" timestamp without time zone,
    "ReceiverType" character varying(20),
    "ReceiverSerial" character varying(20),
    "ReceiverFw" character varying(20),
    "AntennaType" character varying(20),
    "AntennaSerial" character varying(20),
    "AntennaDome" character varying(20),
    "Filename" character varying(50),
    "Interval" numeric NOT NULL,
    "AntennaOffset" numeric,
    "Completion" numeric(7,3) NOT NULL,
    api_id integer NOT NULL
);


--
-- Name: rinex_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rinex_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rinex_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rinex_api_id_seq OWNED BY public.rinex.api_id;


--
-- Name: rinex_proc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.rinex_proc AS
 SELECT rnx."NetworkCode",
    rnx."StationCode",
    rnx."ObservationYear",
    rnx."ObservationMonth",
    rnx."ObservationDay",
    rnx."ObservationDOY",
    rnx."ObservationFYear",
    rnx."ObservationSTime",
    rnx."ObservationETime",
    rnx."ReceiverType",
    rnx."ReceiverSerial",
    rnx."ReceiverFw",
    rnx."AntennaType",
    rnx."AntennaSerial",
    rnx."AntennaDome",
    rnx."Filename",
    rnx."Interval",
    rnx."AntennaOffset",
    rnx."Completion",
    rnx."mI"
   FROM ( SELECT aa."NetworkCode",
            aa."StationCode",
            aa."ObservationYear",
            aa."ObservationMonth",
            aa."ObservationDay",
            aa."ObservationDOY",
            aa."ObservationFYear",
            aa."ObservationSTime",
            aa."ObservationETime",
            aa."ReceiverType",
            aa."ReceiverSerial",
            aa."ReceiverFw",
            aa."AntennaType",
            aa."AntennaSerial",
            aa."AntennaDome",
            aa."Filename",
            aa."Interval",
            aa."AntennaOffset",
            aa."Completion",
            min(aa."Interval") OVER (PARTITION BY aa."NetworkCode", aa."StationCode", aa."ObservationYear", aa."ObservationDOY") AS "mI"
           FROM (public.rinex aa
             LEFT JOIN public.rinex bb ON ((((aa."NetworkCode")::text = (bb."NetworkCode")::text) AND ((aa."StationCode")::text = (bb."StationCode")::text) AND (aa."ObservationYear" = bb."ObservationYear") AND (aa."ObservationDOY" = bb."ObservationDOY") AND (aa."Completion" < bb."Completion"))))
          WHERE (bb."NetworkCode" IS NULL)
          ORDER BY aa."NetworkCode", aa."StationCode", aa."ObservationYear", aa."ObservationDOY", aa."Interval", aa."Completion") rnx
  WHERE (rnx."Interval" = rnx."mI");


--
-- Name: rinex_sources_info; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rinex_sources_info (
    name character varying(20) NOT NULL,
    fqdn character varying NOT NULL,
    protocol character varying NOT NULL,
    username character varying,
    password character varying,
    path character varying,
    format character varying,
    api_id integer NOT NULL
);


--
-- Name: rinex_sources_info_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rinex_sources_info_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rinex_sources_info_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rinex_sources_info_api_id_seq OWNED BY public.rinex_sources_info.api_id;


--
-- Name: rinex_tank_struct; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rinex_tank_struct (
    "Level" integer NOT NULL,
    "KeyCode" character varying(7),
    api_id integer NOT NULL
);


--
-- Name: rinex_tank_struct_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rinex_tank_struct_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rinex_tank_struct_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rinex_tank_struct_api_id_seq OWNED BY public.rinex_tank_struct.api_id;


--
-- Name: sources_formats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources_formats (
    format character varying NOT NULL,
    api_id integer NOT NULL
);


--
-- Name: sources_formats_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sources_formats_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sources_formats_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sources_formats_api_id_seq OWNED BY public.sources_formats.api_id;


--
-- Name: sources_servers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources_servers (
    server_id integer NOT NULL,
    protocol character varying NOT NULL,
    fqdn character varying NOT NULL,
    username character varying,
    password character varying,
    path character varying,
    format character varying DEFAULT 'DEFAULT_FORMAT'::character varying NOT NULL,
    CONSTRAINT sources_servers_protocol_check CHECK (((protocol)::text = ANY (ARRAY[('ftp'::character varying)::text, ('http'::character varying)::text, ('sftp'::character varying)::text, ('https'::character varying)::text, ('ftpa'::character varying)::text, ('FTP'::character varying)::text, ('HTTP'::character varying)::text, ('SFTP'::character varying)::text, ('HTTPS'::character varying)::text, ('FTPA'::character varying)::text])))
);


--
-- Name: sources_servers_server_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sources_servers ALTER COLUMN server_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sources_servers_server_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sources_stations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources_stations (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    try_order smallint DEFAULT 1 NOT NULL,
    server_id integer NOT NULL,
    path character varying,
    format character varying,
    api_id integer NOT NULL
);


--
-- Name: sources_stations_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sources_stations_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sources_stations_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sources_stations_api_id_seq OWNED BY public.sources_stations.api_id;


--
-- Name: stacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stacks (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "Project" character varying(20) NOT NULL,
    "Year" numeric NOT NULL,
    "DOY" numeric NOT NULL,
    "FYear" numeric,
    "X" numeric,
    "Y" numeric,
    "Z" numeric,
    sigmax numeric,
    sigmay numeric,
    sigmaz numeric,
    "VarianceFactor" numeric,
    sigmaxy numeric,
    sigmayz numeric,
    sigmaxz numeric,
    name character varying(20) NOT NULL,
    api_id integer NOT NULL
);


--
-- Name: stacks_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stacks_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stacks_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stacks_api_id_seq OWNED BY public.stacks.api_id;


--
-- Name: stationalias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stationalias (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "StationAlias" character varying(4) NOT NULL,
    api_id integer NOT NULL
);


--
-- Name: stationalias_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stationalias_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stationalias_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stationalias_api_id_seq OWNED BY public.stationalias.api_id;


--
-- Name: stationinfo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stationinfo (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "ReceiverCode" character varying(22) NOT NULL,
    "ReceiverSerial" character varying(22),
    "ReceiverFirmware" character varying(10),
    "AntennaCode" character varying(22) NOT NULL,
    "AntennaSerial" character varying(20),
    "AntennaHeight" numeric(6,4) DEFAULT 0 NOT NULL,
    "AntennaNorth" numeric(12,4) DEFAULT 0 NOT NULL,
    "AntennaEast" numeric(12,4) DEFAULT 0 NOT NULL,
    "HeightCode" character varying,
    "RadomeCode" character varying(7) NOT NULL,
    "DateStart" timestamp without time zone NOT NULL,
    "DateEnd" timestamp without time zone,
    "ReceiverVers" character varying(22),
    "Comments" text,
    api_id integer NOT NULL,
    antdaz numeric(4,1)
);


--
-- Name: stationinfo_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stationinfo_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stationinfo_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stationinfo_api_id_seq OWNED BY public.stationinfo.api_id;


--
-- Name: stations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stations (
    "NetworkCode" character varying(3) NOT NULL,
    "StationCode" character varying(4) NOT NULL,
    "StationName" character varying(40),
    "DateStart" numeric(7,3),
    "DateEnd" numeric(7,3),
    auto_x numeric,
    auto_y numeric,
    auto_z numeric,
    "Harpos_coeff_otl" text,
    lat numeric,
    lon numeric,
    height numeric,
    max_dist numeric,
    dome character varying(9),
    country_code character varying(3),
    marker integer,
    alias character varying(4),
    api_id integer NOT NULL
);


--
-- Name: stations_api_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stations_api_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stations_api_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stations_api_id_seq OWNED BY public.stations.api_id;


--
-- Name: antennas api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antennas ALTER COLUMN api_id SET DEFAULT nextval('public.antennas_api_id_seq'::regclass);


--
-- Name: apr_coords api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apr_coords ALTER COLUMN api_id SET DEFAULT nextval('public.apr_coords_api_id_seq'::regclass);


--
-- Name: aws_sync api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aws_sync ALTER COLUMN api_id SET DEFAULT nextval('public.aws_sync_api_id_seq'::regclass);


--
-- Name: data_source api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source ALTER COLUMN api_id SET DEFAULT nextval('public.data_source_api_id_seq'::regclass);


--
-- Name: earthquakes api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.earthquakes ALTER COLUMN api_id SET DEFAULT nextval('public.earthquakes_api_id_seq'::regclass);


--
-- Name: executions api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.executions ALTER COLUMN api_id SET DEFAULT nextval('public.executions_api_id_seq'::regclass);


--
-- Name: gamit_htc api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_htc ALTER COLUMN api_id SET DEFAULT nextval('public.gamit_htc_api_id_seq'::regclass);


--
-- Name: gamit_soln api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln ALTER COLUMN api_id SET DEFAULT nextval('public.gamit_soln_api_id_seq'::regclass);


--
-- Name: gamit_soln_excl api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln_excl ALTER COLUMN api_id SET DEFAULT nextval('public.gamit_soln_excl_api_id_seq'::regclass);


--
-- Name: gamit_stats api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_stats ALTER COLUMN api_id SET DEFAULT nextval('public.gamit_stats_api_id_seq'::regclass);


--
-- Name: gamit_subnets api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_subnets ALTER COLUMN api_id SET DEFAULT nextval('public.gamit_subnets_api_id_seq'::regclass);


--
-- Name: gamit_ztd api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_ztd ALTER COLUMN api_id SET DEFAULT nextval('public.gamit_ztd_api_id_seq'::regclass);


--
-- Name: keys api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys ALTER COLUMN api_id SET DEFAULT nextval('public.keys_api_id_seq'::regclass);


--
-- Name: locks api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locks ALTER COLUMN api_id SET DEFAULT nextval('public.locks_api_id_seq'::regclass);


--
-- Name: networks api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks ALTER COLUMN api_id SET DEFAULT nextval('public.networks_api_id_seq'::regclass);


--
-- Name: ppp_soln api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln ALTER COLUMN api_id SET DEFAULT nextval('public.ppp_soln_api_id_seq'::regclass);


--
-- Name: ppp_soln_excl api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln_excl ALTER COLUMN api_id SET DEFAULT nextval('public.ppp_soln_excl_api_id_seq'::regclass);


--
-- Name: receivers api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivers ALTER COLUMN api_id SET DEFAULT nextval('public.receivers_api_id_seq'::regclass);


--
-- Name: rinex api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex ALTER COLUMN api_id SET DEFAULT nextval('public.rinex_api_id_seq'::regclass);


--
-- Name: rinex_sources_info api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex_sources_info ALTER COLUMN api_id SET DEFAULT nextval('public.rinex_sources_info_api_id_seq'::regclass);


--
-- Name: rinex_tank_struct api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex_tank_struct ALTER COLUMN api_id SET DEFAULT nextval('public.rinex_tank_struct_api_id_seq'::regclass);


--
-- Name: sources_formats api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_formats ALTER COLUMN api_id SET DEFAULT nextval('public.sources_formats_api_id_seq'::regclass);


--
-- Name: sources_stations api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_stations ALTER COLUMN api_id SET DEFAULT nextval('public.sources_stations_api_id_seq'::regclass);


--
-- Name: stacks api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stacks ALTER COLUMN api_id SET DEFAULT nextval('public.stacks_api_id_seq'::regclass);


--
-- Name: stationalias api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationalias ALTER COLUMN api_id SET DEFAULT nextval('public.stationalias_api_id_seq'::regclass);


--
-- Name: stationinfo api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationinfo ALTER COLUMN api_id SET DEFAULT nextval('public.stationinfo_api_id_seq'::regclass);


--
-- Name: stations api_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations ALTER COLUMN api_id SET DEFAULT nextval('public.stations_api_id_seq'::regclass);


--
-- Name: antennas antennas_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antennas
    ADD CONSTRAINT antennas_api_id_key UNIQUE (api_id);


--
-- Name: antennas antennas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antennas
    ADD CONSTRAINT antennas_pkey PRIMARY KEY ("AntennaCode");


--
-- Name: api_campaigns api_campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_campaigns
    ADD CONSTRAINT api_campaigns_pkey PRIMARY KEY (id);


--
-- Name: api_clustertype api_clustertype_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_clustertype
    ADD CONSTRAINT api_clustertype_name_key UNIQUE (name);


--
-- Name: api_clustertype api_clustertype_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_clustertype
    ADD CONSTRAINT api_clustertype_pkey PRIMARY KEY (id);


--
-- Name: api_country api_country_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_country
    ADD CONSTRAINT api_country_name_key UNIQUE (name);


--
-- Name: api_country api_country_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_country
    ADD CONSTRAINT api_country_pkey PRIMARY KEY (id);


--
-- Name: api_country api_country_three_digits_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_country
    ADD CONSTRAINT api_country_three_digits_code_key UNIQUE (three_digits_code);


--
-- Name: api_country api_country_two_digits_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_country
    ADD CONSTRAINT api_country_two_digits_code_key UNIQUE (two_digits_code);


--
-- Name: api_endpoint api_endpoint_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpoint
    ADD CONSTRAINT api_endpoint_pkey PRIMARY KEY (id);


--
-- Name: api_endpointscluster_endpoints api_endpointscluster_end_endpointscluster_id_endp_bb94e051_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster_endpoints
    ADD CONSTRAINT api_endpointscluster_end_endpointscluster_id_endp_bb94e051_uniq UNIQUE (endpointscluster_id, endpoint_id);


--
-- Name: api_endpointscluster_endpoints api_endpointscluster_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster_endpoints
    ADD CONSTRAINT api_endpointscluster_endpoints_pkey PRIMARY KEY (id);


--
-- Name: api_endpointscluster api_endpointscluster_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster
    ADD CONSTRAINT api_endpointscluster_pkey PRIMARY KEY (id);


--
-- Name: api_monumenttype api_monumenttype_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_monumenttype
    ADD CONSTRAINT api_monumenttype_name_key UNIQUE (name);


--
-- Name: api_monumenttype api_monumenttype_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_monumenttype
    ADD CONSTRAINT api_monumenttype_pkey PRIMARY KEY (id);


--
-- Name: api_person api_person_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_person
    ADD CONSTRAINT api_person_pkey PRIMARY KEY (id);


--
-- Name: api_resource api_resource_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_resource
    ADD CONSTRAINT api_resource_name_key UNIQUE (name);


--
-- Name: api_resource api_resource_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_resource
    ADD CONSTRAINT api_resource_pkey PRIMARY KEY (id);


--
-- Name: api_role_endpoints_clusters api_role_endpoints_clust_role_id_endpointscluster_a2b10f39_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_role_endpoints_clusters
    ADD CONSTRAINT api_role_endpoints_clust_role_id_endpointscluster_a2b10f39_uniq UNIQUE (role_id, endpointscluster_id);


--
-- Name: api_role_endpoints_clusters api_role_endpoints_clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_role_endpoints_clusters
    ADD CONSTRAINT api_role_endpoints_clusters_pkey PRIMARY KEY (id);


--
-- Name: api_role api_role_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_role
    ADD CONSTRAINT api_role_name_key UNIQUE (name);


--
-- Name: api_role api_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_role
    ADD CONSTRAINT api_role_pkey PRIMARY KEY (id);


--
-- Name: api_rolepersonstation api_rolepersonstation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_rolepersonstation
    ADD CONSTRAINT api_rolepersonstation_pkey PRIMARY KEY (id);


--
-- Name: api_stationattachedfiles api_stationattachedfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationattachedfiles
    ADD CONSTRAINT api_stationattachedfiles_pkey PRIMARY KEY (id);


--
-- Name: api_stationimages api_stationimages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationimages
    ADD CONSTRAINT api_stationimages_pkey PRIMARY KEY (id);


--
-- Name: api_stationmeta api_stationmeta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmeta
    ADD CONSTRAINT api_stationmeta_pkey PRIMARY KEY (id);


--
-- Name: api_stationmetagaps api_stationmetagaps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmetagaps
    ADD CONSTRAINT api_stationmetagaps_pkey PRIMARY KEY (id);


--
-- Name: api_stationrole api_stationrole_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationrole
    ADD CONSTRAINT api_stationrole_name_key UNIQUE (name);


--
-- Name: api_stationrole api_stationrole_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationrole
    ADD CONSTRAINT api_stationrole_pkey PRIMARY KEY (id);


--
-- Name: api_stationstatus api_stationstatus_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationstatus
    ADD CONSTRAINT api_stationstatus_name_key UNIQUE (name);


--
-- Name: api_stationstatus api_stationstatus_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationstatus
    ADD CONSTRAINT api_stationstatus_pkey PRIMARY KEY (id);


--
-- Name: api_stationtype api_stationtype_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationtype
    ADD CONSTRAINT api_stationtype_name_key UNIQUE (name);


--
-- Name: api_stationtype api_stationtype_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationtype
    ADD CONSTRAINT api_stationtype_pkey PRIMARY KEY (id);


--
-- Name: api_user_groups api_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_groups
    ADD CONSTRAINT api_user_groups_pkey PRIMARY KEY (id);


--
-- Name: api_user_groups api_user_groups_user_id_group_id_9c7ddfb5_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_groups
    ADD CONSTRAINT api_user_groups_user_id_group_id_9c7ddfb5_uniq UNIQUE (user_id, group_id);


--
-- Name: api_user api_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user
    ADD CONSTRAINT api_user_pkey PRIMARY KEY (id);


--
-- Name: api_user_user_permissions api_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_user_permissions
    ADD CONSTRAINT api_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: api_user_user_permissions api_user_user_permissions_user_id_permission_id_a06dd704_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_user_permissions
    ADD CONSTRAINT api_user_user_permissions_user_id_permission_id_a06dd704_uniq UNIQUE (user_id, permission_id);


--
-- Name: api_user api_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user
    ADD CONSTRAINT api_user_username_key UNIQUE (username);


--
-- Name: api_visitattachedfiles api_visitattachedfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitattachedfiles
    ADD CONSTRAINT api_visitattachedfiles_pkey PRIMARY KEY (id);


--
-- Name: api_visitgnssdatafiles api_visitgnssdatafiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitgnssdatafiles
    ADD CONSTRAINT api_visitgnssdatafiles_pkey PRIMARY KEY (id);


--
-- Name: api_visitimages api_visitimages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitimages
    ADD CONSTRAINT api_visitimages_pkey PRIMARY KEY (id);


--
-- Name: api_visits_people api_visits_people_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits_people
    ADD CONSTRAINT api_visits_people_pkey PRIMARY KEY (id);


--
-- Name: api_visits_people api_visits_people_visits_id_person_id_4a57a25d_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits_people
    ADD CONSTRAINT api_visits_people_visits_id_person_id_4a57a25d_uniq UNIQUE (visits_id, person_id);


--
-- Name: api_visits api_visits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits
    ADD CONSTRAINT api_visits_pkey PRIMARY KEY (id);


--
-- Name: apr_coords apr_coords_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apr_coords
    ADD CONSTRAINT apr_coords_api_id_key UNIQUE (api_id);


--
-- Name: apr_coords apr_coords_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apr_coords
    ADD CONSTRAINT apr_coords_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Year", "DOY");


--
-- Name: auditlog_logentry auditlog_logentry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditlog_logentry
    ADD CONSTRAINT auditlog_logentry_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: aws_sync aws_sync_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aws_sync
    ADD CONSTRAINT aws_sync_api_id_key UNIQUE (api_id);


--
-- Name: aws_sync aws_sync_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aws_sync
    ADD CONSTRAINT aws_sync_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Year", "DOY");


--
-- Name: data_source data_source_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source
    ADD CONSTRAINT data_source_api_id_key UNIQUE (api_id);


--
-- Name: data_source data_source_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source
    ADD CONSTRAINT data_source_pkey PRIMARY KEY ("NetworkCode", "StationCode", try_order);


--
-- Name: stationinfo date_chk; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.stationinfo
    ADD CONSTRAINT date_chk CHECK (("DateEnd" > "DateStart")) NOT VALID;


--
-- Name: django_admin_log django_admin_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_pkey PRIMARY KEY (id);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: earthquakes earthquakes_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.earthquakes
    ADD CONSTRAINT earthquakes_api_id_key UNIQUE (api_id);


--
-- Name: earthquakes earthquakes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.earthquakes
    ADD CONSTRAINT earthquakes_pkey PRIMARY KEY (date, lat, lon);


--
-- Name: etm_params etm_params_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etm_params
    ADD CONSTRAINT etm_params_pkey PRIMARY KEY (uid);


--
-- Name: etms etmsv2_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etms
    ADD CONSTRAINT etmsv2_pkey PRIMARY KEY (uid);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (event_id, "EventDate");


--
-- Name: executions executions_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.executions
    ADD CONSTRAINT executions_api_id_key UNIQUE (api_id);


--
-- Name: gamit_htc gamit_htc_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_htc
    ADD CONSTRAINT gamit_htc_api_id_key UNIQUE (api_id);


--
-- Name: gamit_htc gamit_htc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_htc
    ADD CONSTRAINT gamit_htc_pkey PRIMARY KEY ("AntennaCode", "HeightCode");


--
-- Name: gamit_soln gamit_soln_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln
    ADD CONSTRAINT gamit_soln_api_id_key UNIQUE (api_id);


--
-- Name: gamit_soln_excl gamit_soln_excl_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln_excl
    ADD CONSTRAINT gamit_soln_excl_api_id_key UNIQUE (api_id);


--
-- Name: gamit_soln_excl gamit_soln_excl_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln_excl
    ADD CONSTRAINT gamit_soln_excl_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Project", "Year", "DOY");


--
-- Name: gamit_soln gamit_soln_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln
    ADD CONSTRAINT gamit_soln_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Project", "Year", "DOY");


--
-- Name: gamit_stats gamit_stats_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_stats
    ADD CONSTRAINT gamit_stats_api_id_key UNIQUE (api_id);


--
-- Name: gamit_stats gamit_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_stats
    ADD CONSTRAINT gamit_stats_pkey PRIMARY KEY ("Project", subnet, "Year", "DOY", system);


--
-- Name: gamit_subnets gamit_subnets_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_subnets
    ADD CONSTRAINT gamit_subnets_api_id_key UNIQUE (api_id);


--
-- Name: gamit_subnets gamit_subnets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_subnets
    ADD CONSTRAINT gamit_subnets_pkey PRIMARY KEY ("Project", subnet, "Year", "DOY");


--
-- Name: gamit_ztd gamit_ztd_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_ztd
    ADD CONSTRAINT gamit_ztd_api_id_key UNIQUE (api_id);


--
-- Name: gamit_ztd gamit_ztd_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_ztd
    ADD CONSTRAINT gamit_ztd_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Date", "Project", "Year", "DOY");


--
-- Name: keys keys_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_api_id_key UNIQUE (api_id);


--
-- Name: keys keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_pkey PRIMARY KEY ("KeyCode");


--
-- Name: locks locks_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locks
    ADD CONSTRAINT locks_api_id_key UNIQUE (api_id);


--
-- Name: locks locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locks
    ADD CONSTRAINT locks_pkey PRIMARY KEY (filename);


--
-- Name: networks networks_NetworkCode_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks
    ADD CONSTRAINT "networks_NetworkCode_pkey" PRIMARY KEY ("NetworkCode");


--
-- Name: networks networks_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks
    ADD CONSTRAINT networks_api_id_key UNIQUE (api_id);


--
-- Name: api_endpoint path_method_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpoint
    ADD CONSTRAINT path_method_unique UNIQUE (path, method);


--
-- Name: ppp_soln ppp_soln_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln
    ADD CONSTRAINT ppp_soln_api_id_key UNIQUE (api_id);


--
-- Name: ppp_soln_excl ppp_soln_excl_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln_excl
    ADD CONSTRAINT ppp_soln_excl_api_id_key UNIQUE (api_id);


--
-- Name: ppp_soln_excl ppp_soln_excl_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln_excl
    ADD CONSTRAINT ppp_soln_excl_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Year", "DOY");


--
-- Name: ppp_soln ppp_soln_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln
    ADD CONSTRAINT ppp_soln_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Year", "DOY", "ReferenceFrame");


--
-- Name: receivers receivers_ReceiverCode_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivers
    ADD CONSTRAINT "receivers_ReceiverCode_pkey" PRIMARY KEY ("ReceiverCode");


--
-- Name: receivers receivers_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivers
    ADD CONSTRAINT receivers_api_id_key UNIQUE (api_id);


--
-- Name: api_endpointscluster resource_cluster_type_role_type_description_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster
    ADD CONSTRAINT resource_cluster_type_role_type_description_unique UNIQUE (resource_id, cluster_type_id, role_type, description);


--
-- Name: rinex rinex_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex
    ADD CONSTRAINT rinex_api_id_key UNIQUE (api_id);


--
-- Name: rinex rinex_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex
    ADD CONSTRAINT rinex_pkey PRIMARY KEY ("NetworkCode", "StationCode", "ObservationYear", "ObservationDOY", "Interval", "Completion");


--
-- Name: rinex_sources_info rinex_sources_info_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex_sources_info
    ADD CONSTRAINT rinex_sources_info_api_id_key UNIQUE (api_id);


--
-- Name: rinex_sources_info rinex_sources_info_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex_sources_info
    ADD CONSTRAINT rinex_sources_info_pkey PRIMARY KEY (name);


--
-- Name: rinex_tank_struct rinex_tank_struct_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex_tank_struct
    ADD CONSTRAINT rinex_tank_struct_api_id_key UNIQUE (api_id);


--
-- Name: rinex_tank_struct rinex_tank_struct_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex_tank_struct
    ADD CONSTRAINT rinex_tank_struct_pkey PRIMARY KEY ("Level");


--
-- Name: api_rolepersonstation role_person_station_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_rolepersonstation
    ADD CONSTRAINT role_person_station_unique UNIQUE (role_id, person_id, station_id);


--
-- Name: sources_formats sources_formats_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_formats
    ADD CONSTRAINT sources_formats_api_id_key UNIQUE (api_id);


--
-- Name: sources_formats sources_formats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_formats
    ADD CONSTRAINT sources_formats_pkey PRIMARY KEY (format);


--
-- Name: sources_servers sources_servers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_servers
    ADD CONSTRAINT sources_servers_pkey PRIMARY KEY (server_id);


--
-- Name: sources_stations sources_stations_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_stations
    ADD CONSTRAINT sources_stations_api_id_key UNIQUE (api_id);


--
-- Name: sources_stations sources_stations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_stations
    ADD CONSTRAINT sources_stations_pkey PRIMARY KEY ("NetworkCode", "StationCode", try_order);


--
-- Name: stacks stacks_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stacks
    ADD CONSTRAINT stacks_api_id_key UNIQUE (api_id);


--
-- Name: stacks stacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stacks
    ADD CONSTRAINT stacks_pkey PRIMARY KEY ("NetworkCode", "StationCode", "Year", "DOY", name);


--
-- Name: api_visits station_date_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits
    ADD CONSTRAINT station_date_unique UNIQUE (station_id, date);


--
-- Name: api_stationattachedfiles station_filename_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationattachedfiles
    ADD CONSTRAINT station_filename_unique UNIQUE (station_id, filename);


--
-- Name: api_stationimages station_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationimages
    ADD CONSTRAINT station_name_unique UNIQUE (station_id, name);


--
-- Name: api_stationmeta station_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmeta
    ADD CONSTRAINT station_unique UNIQUE (station_id);


--
-- Name: stationalias stationalias_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationalias
    ADD CONSTRAINT stationalias_api_id_key UNIQUE (api_id);


--
-- Name: stationalias stationalias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationalias
    ADD CONSTRAINT stationalias_pkey PRIMARY KEY ("NetworkCode", "StationCode");


--
-- Name: stationalias stationalias_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationalias
    ADD CONSTRAINT stationalias_uniq UNIQUE ("StationAlias");


--
-- Name: stationinfo stationinfo_NetworkCode_StationCode_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationinfo
    ADD CONSTRAINT "stationinfo_NetworkCode_StationCode_pkey" PRIMARY KEY ("NetworkCode", "StationCode", "DateStart");


--
-- Name: stationinfo stationinfo_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationinfo
    ADD CONSTRAINT stationinfo_api_id_key UNIQUE (api_id);


--
-- Name: stations stations_NetworkCode_StationCode_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT "stations_NetworkCode_StationCode_pkey" PRIMARY KEY ("NetworkCode", "StationCode");


--
-- Name: stations stations_api_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT stations_api_id_key UNIQUE (api_id);


--
-- Name: api_visitgnssdatafiles visit_filename_gnss_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitgnssdatafiles
    ADD CONSTRAINT visit_filename_gnss_unique UNIQUE (visit_id, filename);


--
-- Name: api_visitattachedfiles visit_filename_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitattachedfiles
    ADD CONSTRAINT visit_filename_unique UNIQUE (visit_id, filename);


--
-- Name: api_visitimages visit_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitimages
    ADD CONSTRAINT visit_name_unique UNIQUE (visit_id, name);


--
-- Name: Filename; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "Filename" ON public.rinex USING btree ("Filename" varchar_ops);


--
-- Name: api_clustertype_name_95bb2535_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_clustertype_name_95bb2535_like ON public.api_clustertype USING btree (name varchar_pattern_ops);


--
-- Name: api_country_name_6a70666f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_country_name_6a70666f_like ON public.api_country USING btree (name varchar_pattern_ops);


--
-- Name: api_country_three_digits_code_b42e8ca2_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_country_three_digits_code_b42e8ca2_like ON public.api_country USING btree (three_digits_code varchar_pattern_ops);


--
-- Name: api_country_two_digits_code_08ee4eef_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_country_two_digits_code_08ee4eef_like ON public.api_country USING btree (two_digits_code varchar_pattern_ops);


--
-- Name: api_endpointscluster_cluster_type_id_1e49af86; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_endpointscluster_cluster_type_id_1e49af86 ON public.api_endpointscluster USING btree (cluster_type_id);


--
-- Name: api_endpointscluster_endpoints_endpoint_id_6657e51f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_endpointscluster_endpoints_endpoint_id_6657e51f ON public.api_endpointscluster_endpoints USING btree (endpoint_id);


--
-- Name: api_endpointscluster_endpoints_endpointscluster_id_9d81b5e9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_endpointscluster_endpoints_endpointscluster_id_9d81b5e9 ON public.api_endpointscluster_endpoints USING btree (endpointscluster_id);


--
-- Name: api_endpointscluster_resource_id_5bd92927; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_endpointscluster_resource_id_5bd92927 ON public.api_endpointscluster USING btree (resource_id);


--
-- Name: api_monumenttype_name_b69135a7_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_monumenttype_name_b69135a7_like ON public.api_monumenttype USING btree (name varchar_pattern_ops);


--
-- Name: api_person_user_id_c3411bd2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_person_user_id_c3411bd2 ON public.api_person USING btree (user_id);


--
-- Name: api_resource_name_ffa965d2_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_resource_name_ffa965d2_like ON public.api_resource USING btree (name varchar_pattern_ops);


--
-- Name: api_role_endpoints_clusters_endpointscluster_id_755b18d0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_role_endpoints_clusters_endpointscluster_id_755b18d0 ON public.api_role_endpoints_clusters USING btree (endpointscluster_id);


--
-- Name: api_role_endpoints_clusters_role_id_49c77584; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_role_endpoints_clusters_role_id_49c77584 ON public.api_role_endpoints_clusters USING btree (role_id);


--
-- Name: api_role_name_b5227b52_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_role_name_b5227b52_like ON public.api_role USING btree (name varchar_pattern_ops);


--
-- Name: api_rolepersonstation_person_id_0221bab2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_rolepersonstation_person_id_0221bab2 ON public.api_rolepersonstation USING btree (person_id);


--
-- Name: api_rolepersonstation_role_id_b85fba4f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_rolepersonstation_role_id_b85fba4f ON public.api_rolepersonstation USING btree (role_id);


--
-- Name: api_rolepersonstation_station_id_19834f7f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_rolepersonstation_station_id_19834f7f ON public.api_rolepersonstation USING btree (station_id);


--
-- Name: api_stationattachedfiles_station_id_c8c09298; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationattachedfiles_station_id_c8c09298 ON public.api_stationattachedfiles USING btree (station_id);


--
-- Name: api_stationimages_station_id_af6b1a21; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationimages_station_id_af6b1a21 ON public.api_stationimages USING btree (station_id);


--
-- Name: api_stationmeta_monument_type_id_763f1881; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationmeta_monument_type_id_763f1881 ON public.api_stationmeta USING btree (monument_type_id);


--
-- Name: api_stationmeta_station_id_6a9e6239; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationmeta_station_id_6a9e6239 ON public.api_stationmeta USING btree (station_id);


--
-- Name: api_stationmeta_station_type_id_11f0671d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationmeta_station_type_id_11f0671d ON public.api_stationmeta USING btree (station_type_id);


--
-- Name: api_stationmeta_status_id_7e2c16db; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationmeta_status_id_7e2c16db ON public.api_stationmeta USING btree (status_id);


--
-- Name: api_stationmetagaps_station_meta_id_654c7394; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationmetagaps_station_meta_id_654c7394 ON public.api_stationmetagaps USING btree (station_meta_id);


--
-- Name: api_stationrole_name_efed581e_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationrole_name_efed581e_like ON public.api_stationrole USING btree (name varchar_pattern_ops);


--
-- Name: api_stationstatus_name_9c4e75bd_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationstatus_name_9c4e75bd_like ON public.api_stationstatus USING btree (name varchar_pattern_ops);


--
-- Name: api_stationtype_name_07a83d18_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_stationtype_name_07a83d18_like ON public.api_stationtype USING btree (name varchar_pattern_ops);


--
-- Name: api_user_groups_group_id_3af85785; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_user_groups_group_id_3af85785 ON public.api_user_groups USING btree (group_id);


--
-- Name: api_user_groups_user_id_a5ff39fa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_user_groups_user_id_a5ff39fa ON public.api_user_groups USING btree (user_id);


--
-- Name: api_user_role_id_0b60389b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_user_role_id_0b60389b ON public.api_user USING btree (role_id);


--
-- Name: api_user_user_permissions_permission_id_305b7fea; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_user_user_permissions_permission_id_305b7fea ON public.api_user_user_permissions USING btree (permission_id);


--
-- Name: api_user_user_permissions_user_id_f3945d65; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_user_user_permissions_user_id_f3945d65 ON public.api_user_user_permissions USING btree (user_id);


--
-- Name: api_user_username_cf4e88d2_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_user_username_cf4e88d2_like ON public.api_user USING btree (username varchar_pattern_ops);


--
-- Name: api_visitattachedfiles_visit_id_78032a67; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_visitattachedfiles_visit_id_78032a67 ON public.api_visitattachedfiles USING btree (visit_id);


--
-- Name: api_visitgnssdatafiles_visit_id_d1beb947; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_visitgnssdatafiles_visit_id_d1beb947 ON public.api_visitgnssdatafiles USING btree (visit_id);


--
-- Name: api_visitimages_visit_id_86ae72e5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_visitimages_visit_id_86ae72e5 ON public.api_visitimages USING btree (visit_id);


--
-- Name: api_visits_campaign_id_a7379fb8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_visits_campaign_id_a7379fb8 ON public.api_visits USING btree (campaign_id);


--
-- Name: api_visits_people_person_id_ffe688b6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_visits_people_person_id_ffe688b6 ON public.api_visits_people USING btree (person_id);


--
-- Name: api_visits_people_visits_id_69447804; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_visits_people_visits_id_69447804 ON public.api_visits_people USING btree (visits_id);


--
-- Name: api_visits_station_id_5179987a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX api_visits_station_id_5179987a ON public.api_visits USING btree (station_id);


--
-- Name: apr_coords_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX apr_coords_date_idx ON public.apr_coords USING btree ("NetworkCode", "StationCode", "Year", "DOY");


--
-- Name: auditlog_logentry_action_229afe39; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_action_229afe39 ON public.auditlog_logentry USING btree (action);


--
-- Name: auditlog_logentry_actor_id_959271d2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_actor_id_959271d2 ON public.auditlog_logentry USING btree (actor_id);


--
-- Name: auditlog_logentry_cid_9f467263; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_cid_9f467263 ON public.auditlog_logentry USING btree (cid);


--
-- Name: auditlog_logentry_cid_9f467263_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_cid_9f467263_like ON public.auditlog_logentry USING btree (cid varchar_pattern_ops);


--
-- Name: auditlog_logentry_content_type_id_75830218; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_content_type_id_75830218 ON public.auditlog_logentry USING btree (content_type_id);


--
-- Name: auditlog_logentry_object_id_09c2eee8; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_object_id_09c2eee8 ON public.auditlog_logentry USING btree (object_id);


--
-- Name: auditlog_logentry_object_pk_6e3219c0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_object_pk_6e3219c0 ON public.auditlog_logentry USING btree (object_pk);


--
-- Name: auditlog_logentry_object_pk_6e3219c0_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_object_pk_6e3219c0_like ON public.auditlog_logentry USING btree (object_pk varchar_pattern_ops);


--
-- Name: auditlog_logentry_timestamp_37867bb0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditlog_logentry_timestamp_37867bb0 ON public.auditlog_logentry USING btree ("timestamp");


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: aws_sync_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aws_sync_idx ON public.aws_sync USING btree ("NetworkCode", "StationCode", "StationAlias", "Year", "DOY");


--
-- Name: django_admin_log_content_type_id_c4bce8eb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_admin_log_content_type_id_c4bce8eb ON public.django_admin_log USING btree (content_type_id);


--
-- Name: django_admin_log_user_id_c564eba6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_admin_log_user_id_c564eba6 ON public.django_admin_log USING btree (user_id);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: etm_params_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX etm_params_idx ON public.etm_params USING btree ("NetworkCode", "StationCode", soln, object);


--
-- Name: events_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX events_index ON public.events USING btree ("NetworkCode", "StationCode", "Year", "DOY");


--
-- Name: gamit_ztd_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX gamit_ztd_idx ON public.gamit_ztd USING btree ("Project", "Year", "DOY");


--
-- Name: network_station; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX network_station ON public.rinex USING btree ("NetworkCode" varchar_ops, "StationCode" varchar_ops);


--
-- Name: ppp_soln_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ppp_soln_idx ON public.ppp_soln USING btree ("NetworkCode" COLLATE "C" varchar_ops, "StationCode" COLLATE "C" varchar_ops);


--
-- Name: ppp_soln_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ppp_soln_order ON public.ppp_soln USING btree ("NetworkCode", "StationCode", "Year", "DOY");


--
-- Name: rinex_obs_comp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rinex_obs_comp_idx ON public.rinex USING btree ("NetworkCode", "StationCode", "ObservationYear", "ObservationDOY", "Completion");


--
-- Name: rinex_obs_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rinex_obs_idx ON public.rinex USING btree ("NetworkCode", "StationCode", "ObservationYear", "ObservationDOY");


--
-- Name: stacks_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stacks_idx ON public.stacks USING btree ("Year", "DOY");


--
-- Name: stations_NetworkCode_StationCode_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "stations_NetworkCode_StationCode_idx" ON public.stations USING btree ("NetworkCode", "StationCode");


--
-- Name: stations_country_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stations_country_code_idx ON public.stations USING btree (country_code);


--
-- Name: rinex update_has_gaps_update_needed_field_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_has_gaps_update_needed_field_trigger AFTER INSERT OR DELETE OR UPDATE ON public.rinex FOR EACH ROW EXECUTE FUNCTION public.update_has_gaps_update_needed_field();


--
-- Name: stationinfo update_has_gaps_update_needed_field_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_has_gaps_update_needed_field_trigger AFTER INSERT OR DELETE OR UPDATE ON public.stationinfo FOR EACH ROW EXECUTE FUNCTION public.update_has_gaps_update_needed_field();


--
-- Name: stationinfo update_has_stationinfo_field_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_has_stationinfo_field_trigger AFTER INSERT OR DELETE OR UPDATE ON public.stationinfo FOR EACH ROW EXECUTE FUNCTION public.update_has_stationinfo_field();


--
-- Name: stations update_has_stationinfo_field_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_has_stationinfo_field_trigger BEFORE DELETE ON public.stations FOR EACH ROW EXECUTE FUNCTION public.delete_rows_referencing_stations();


--
-- Name: rinex update_stations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_stations AFTER INSERT ON public.rinex FOR EACH ROW EXECUTE FUNCTION public.update_timespan_trigg();


--
-- Name: stationalias verify_stationalias; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER verify_stationalias BEFORE INSERT OR UPDATE ON public.stationalias FOR EACH ROW EXECUTE FUNCTION public.stationalias_check();


--
-- Name: stations NetworkCode; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT "NetworkCode" FOREIGN KEY ("NetworkCode") REFERENCES public.networks("NetworkCode") MATCH FULL ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: gamit_htc antenna_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_htc
    ADD CONSTRAINT antenna_fk FOREIGN KEY ("AntennaCode") REFERENCES public.antennas("AntennaCode") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: api_endpointscluster api_endpointscluster_cluster_type_id_1e49af86_fk_api_clust; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster
    ADD CONSTRAINT api_endpointscluster_cluster_type_id_1e49af86_fk_api_clust FOREIGN KEY (cluster_type_id) REFERENCES public.api_clustertype(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_endpointscluster_endpoints api_endpointscluster_endpoint_id_6657e51f_fk_api_endpo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster_endpoints
    ADD CONSTRAINT api_endpointscluster_endpoint_id_6657e51f_fk_api_endpo FOREIGN KEY (endpoint_id) REFERENCES public.api_endpoint(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_endpointscluster_endpoints api_endpointscluster_endpointscluster_id_9d81b5e9_fk_api_endpo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster_endpoints
    ADD CONSTRAINT api_endpointscluster_endpointscluster_id_9d81b5e9_fk_api_endpo FOREIGN KEY (endpointscluster_id) REFERENCES public.api_endpointscluster(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_endpointscluster api_endpointscluster_resource_id_5bd92927_fk_api_resource_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_endpointscluster
    ADD CONSTRAINT api_endpointscluster_resource_id_5bd92927_fk_api_resource_id FOREIGN KEY (resource_id) REFERENCES public.api_resource(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_person api_person_user_id_c3411bd2_fk_api_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_person
    ADD CONSTRAINT api_person_user_id_c3411bd2_fk_api_user_id FOREIGN KEY (user_id) REFERENCES public.api_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_role_endpoints_clusters api_role_endpoints_c_endpointscluster_id_755b18d0_fk_api_endpo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_role_endpoints_clusters
    ADD CONSTRAINT api_role_endpoints_c_endpointscluster_id_755b18d0_fk_api_endpo FOREIGN KEY (endpointscluster_id) REFERENCES public.api_endpointscluster(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_role_endpoints_clusters api_role_endpoints_clusters_role_id_49c77584_fk_api_role_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_role_endpoints_clusters
    ADD CONSTRAINT api_role_endpoints_clusters_role_id_49c77584_fk_api_role_id FOREIGN KEY (role_id) REFERENCES public.api_role(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_rolepersonstation api_rolepersonstation_person_id_0221bab2_fk_api_person_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_rolepersonstation
    ADD CONSTRAINT api_rolepersonstation_person_id_0221bab2_fk_api_person_id FOREIGN KEY (person_id) REFERENCES public.api_person(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_rolepersonstation api_rolepersonstation_role_id_b85fba4f_fk_api_stationrole_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_rolepersonstation
    ADD CONSTRAINT api_rolepersonstation_role_id_b85fba4f_fk_api_stationrole_id FOREIGN KEY (role_id) REFERENCES public.api_stationrole(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_rolepersonstation api_rolepersonstation_station_id_19834f7f_fk_stations_api_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_rolepersonstation
    ADD CONSTRAINT api_rolepersonstation_station_id_19834f7f_fk_stations_api_id FOREIGN KEY (station_id) REFERENCES public.stations(api_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_stationattachedfiles api_stationattachedfiles_station_id_c8c09298_fk_stations_api_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationattachedfiles
    ADD CONSTRAINT api_stationattachedfiles_station_id_c8c09298_fk_stations_api_id FOREIGN KEY (station_id) REFERENCES public.stations(api_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_stationimages api_stationimages_station_id_af6b1a21_fk_stations_api_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationimages
    ADD CONSTRAINT api_stationimages_station_id_af6b1a21_fk_stations_api_id FOREIGN KEY (station_id) REFERENCES public.stations(api_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_stationmeta api_stationmeta_monument_type_id_763f1881_fk_api_monum; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmeta
    ADD CONSTRAINT api_stationmeta_monument_type_id_763f1881_fk_api_monum FOREIGN KEY (monument_type_id) REFERENCES public.api_monumenttype(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_stationmeta api_stationmeta_station_id_6a9e6239_fk_stations_api_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmeta
    ADD CONSTRAINT api_stationmeta_station_id_6a9e6239_fk_stations_api_id FOREIGN KEY (station_id) REFERENCES public.stations(api_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_stationmeta api_stationmeta_station_type_id_11f0671d_fk_api_stationtype_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmeta
    ADD CONSTRAINT api_stationmeta_station_type_id_11f0671d_fk_api_stationtype_id FOREIGN KEY (station_type_id) REFERENCES public.api_stationtype(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_stationmeta api_stationmeta_status_id_7e2c16db_fk_api_stationstatus_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmeta
    ADD CONSTRAINT api_stationmeta_status_id_7e2c16db_fk_api_stationstatus_id FOREIGN KEY (status_id) REFERENCES public.api_stationstatus(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_stationmetagaps api_stationmetagaps_station_meta_id_654c7394_fk_api_stati; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_stationmetagaps
    ADD CONSTRAINT api_stationmetagaps_station_meta_id_654c7394_fk_api_stati FOREIGN KEY (station_meta_id) REFERENCES public.api_stationmeta(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_user_groups api_user_groups_group_id_3af85785_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_groups
    ADD CONSTRAINT api_user_groups_group_id_3af85785_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_user_groups api_user_groups_user_id_a5ff39fa_fk_api_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_groups
    ADD CONSTRAINT api_user_groups_user_id_a5ff39fa_fk_api_user_id FOREIGN KEY (user_id) REFERENCES public.api_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_user api_user_role_id_0b60389b_fk_api_role_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user
    ADD CONSTRAINT api_user_role_id_0b60389b_fk_api_role_id FOREIGN KEY (role_id) REFERENCES public.api_role(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_user_user_permissions api_user_user_permis_permission_id_305b7fea_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_user_permissions
    ADD CONSTRAINT api_user_user_permis_permission_id_305b7fea_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_user_user_permissions api_user_user_permissions_user_id_f3945d65_fk_api_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_user_user_permissions
    ADD CONSTRAINT api_user_user_permissions_user_id_f3945d65_fk_api_user_id FOREIGN KEY (user_id) REFERENCES public.api_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_visitattachedfiles api_visitattachedfiles_visit_id_78032a67_fk_api_visits_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitattachedfiles
    ADD CONSTRAINT api_visitattachedfiles_visit_id_78032a67_fk_api_visits_id FOREIGN KEY (visit_id) REFERENCES public.api_visits(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_visitgnssdatafiles api_visitgnssdatafiles_visit_id_d1beb947_fk_api_visits_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitgnssdatafiles
    ADD CONSTRAINT api_visitgnssdatafiles_visit_id_d1beb947_fk_api_visits_id FOREIGN KEY (visit_id) REFERENCES public.api_visits(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_visitimages api_visitimages_visit_id_86ae72e5_fk_api_visits_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visitimages
    ADD CONSTRAINT api_visitimages_visit_id_86ae72e5_fk_api_visits_id FOREIGN KEY (visit_id) REFERENCES public.api_visits(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_visits api_visits_campaign_id_a7379fb8_fk_api_campaigns_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits
    ADD CONSTRAINT api_visits_campaign_id_a7379fb8_fk_api_campaigns_id FOREIGN KEY (campaign_id) REFERENCES public.api_campaigns(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_visits_people api_visits_people_person_id_ffe688b6_fk_api_person_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits_people
    ADD CONSTRAINT api_visits_people_person_id_ffe688b6_fk_api_person_id FOREIGN KEY (person_id) REFERENCES public.api_person(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_visits_people api_visits_people_visits_id_69447804_fk_api_visits_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits_people
    ADD CONSTRAINT api_visits_people_visits_id_69447804_fk_api_visits_id FOREIGN KEY (visits_id) REFERENCES public.api_visits(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: api_visits api_visits_station_id_5179987a_fk_stations_api_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_visits
    ADD CONSTRAINT api_visits_station_id_5179987a_fk_stations_api_id FOREIGN KEY (station_id) REFERENCES public.stations(api_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: apr_coords apr_coords_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apr_coords
    ADD CONSTRAINT "apr_coords_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode");


--
-- Name: auditlog_logentry auditlog_logentry_actor_id_959271d2_fk_api_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditlog_logentry
    ADD CONSTRAINT auditlog_logentry_actor_id_959271d2_fk_api_user_id FOREIGN KEY (actor_id) REFERENCES public.api_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auditlog_logentry auditlog_logentry_content_type_id_75830218_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditlog_logentry
    ADD CONSTRAINT auditlog_logentry_content_type_id_75830218_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: data_source data_source_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source
    ADD CONSTRAINT "data_source_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: django_admin_log django_admin_log_content_type_id_c4bce8eb_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_content_type_id_c4bce8eb_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: django_admin_log django_admin_log_user_id_c564eba6_fk_api_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_user_id_c564eba6_fk_api_user_id FOREIGN KEY (user_id) REFERENCES public.api_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: etms etms_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etms
    ADD CONSTRAINT etms_fk FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stations fk_country_code; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT fk_country_code FOREIGN KEY (country_code) REFERENCES public.api_country(three_digits_code);


--
-- Name: gamit_soln gamit_soln_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln
    ADD CONSTRAINT "gamit_soln_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: gamit_soln_excl gamit_soln_excl_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_soln_excl
    ADD CONSTRAINT "gamit_soln_excl_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode", "Project", "Year", "DOY") REFERENCES public.gamit_soln("NetworkCode", "StationCode", "Project", "Year", "DOY") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: gamit_ztd gamit_ztd_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gamit_ztd
    ADD CONSTRAINT "gamit_ztd_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode");


--
-- Name: locks locks_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locks
    ADD CONSTRAINT "locks_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ppp_soln ppp_soln_NetworkName_StationCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln
    ADD CONSTRAINT "ppp_soln_NetworkName_StationCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: ppp_soln_excl ppp_soln_excl_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ppp_soln_excl
    ADD CONSTRAINT "ppp_soln_excl_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: rinex rinex_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex
    ADD CONSTRAINT "rinex_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: rinex_tank_struct rinex_tank_struct_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rinex_tank_struct
    ADD CONSTRAINT rinex_tank_struct_key_fkey FOREIGN KEY ("KeyCode") REFERENCES public.keys("KeyCode");


--
-- Name: sources_servers sources_servers_format_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_servers
    ADD CONSTRAINT sources_servers_format_fkey FOREIGN KEY (format) REFERENCES public.sources_formats(format);


--
-- Name: sources_stations sources_stations_NetworkCode_StationCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_stations
    ADD CONSTRAINT "sources_stations_NetworkCode_StationCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode");


--
-- Name: sources_stations sources_stations_format_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_stations
    ADD CONSTRAINT sources_stations_format_fkey FOREIGN KEY (format) REFERENCES public.sources_formats(format);


--
-- Name: sources_stations sources_stations_server_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources_stations
    ADD CONSTRAINT sources_stations_server_id_fkey FOREIGN KEY (server_id) REFERENCES public.sources_servers(server_id);


--
-- Name: stacks stacks_NetworkCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stacks
    ADD CONSTRAINT "stacks_NetworkCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stacks stacks_gamit_soln_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stacks
    ADD CONSTRAINT stacks_gamit_soln_fkey FOREIGN KEY ("Year", "DOY", "StationCode", "Project", "NetworkCode") REFERENCES public.gamit_soln("Year", "DOY", "StationCode", "Project", "NetworkCode") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: stationalias stationalias_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationalias
    ADD CONSTRAINT stationalias_fk FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stationinfo stationinfo_AntennaCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationinfo
    ADD CONSTRAINT "stationinfo_AntennaCode_fkey" FOREIGN KEY ("AntennaCode") REFERENCES public.antennas("AntennaCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stationinfo stationinfo_NetworkCode_StationCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationinfo
    ADD CONSTRAINT "stationinfo_NetworkCode_StationCode_fkey" FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: stationinfo stationinfo_ReceiverCode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stationinfo
    ADD CONSTRAINT "stationinfo_ReceiverCode_fkey" FOREIGN KEY ("ReceiverCode") REFERENCES public.receivers("ReceiverCode") ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: etm_params stations_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.etm_params
    ADD CONSTRAINT stations_fk FOREIGN KEY ("NetworkCode", "StationCode") REFERENCES public.stations("NetworkCode", "StationCode");


--
-- PostgreSQL database dump complete
--

