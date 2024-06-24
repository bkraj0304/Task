-- Extract data for the specified vessel and voyage, and exclude records with non-null allocatedVoyageId.-- 
CREATE TABLE voyages (
    id INT,
    event VARCHAR(50),
    dateStamp INT,
    timeStamp FLOAT,
    voyage_From VARCHAR(50),
    lat DECIMAL(9,6),
    lon DECIMAL(9,6),
    imo_num VARCHAR(20),
    voyage_Id VARCHAR(20),
    allocatedVoyageId VARCHAR(20)
);

INSERT INTO voyages VALUES
(1, 'SOSP', 43831, 0.708333, 'Port A', 34.0522, -118.2437, '9434761', '6', NULL),
(2, 'EOSP', 43831, 0.791667, 'Port A', 34.0522, -118.2437, '9434761', '6', NULL),
(3, 'SOSP', 43832, 0.333333, 'Port B', 36.7783, -119.4179, '9434761', '6', NULL),
(4, 'EOSP', 43832, 0.583333, 'Port B', 36.7783, -119.4179, '9434761', '6', NULL);

SELECT * FROM voyages;
-- ////////////////////////////////////////////-- 
-- Calculate precise UTC date-times for events and generate time durations between key events.--  
SELECT 
    e1.id,
    e1.event,
    FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) AS utc_datetime,
    e1.voyage_From,
    e1.lat,
    e1.lon,
    e1.imo_num,
    e1.voyage_Id,
    e2.event AS next_event,
    FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400) AS next_utc_datetime,
    TIMESTAMPDIFF(SECOND, FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400), FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400)) AS duration_seconds
FROM 
    voyages e1
LEFT JOIN 
    voyages e2
ON 
    e1.voyage_Id = e2.voyage_Id 
    AND FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) < FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400)
WHERE 
    e1.imo_num = '9434761'
    AND e1.voyage_Id = '6'
    AND e1.allocatedVoyageId IS NULL
    AND e2.allocatedVoyageId IS NULL
ORDER BY 
    utc_datetime;

/////////////////////////////////////////////////////////////////////-- 
-- Identify and segment different voyage stages based on a series of 'SOSP' (Start of Sea Passage) and 'EOSP' (End of Sea Passage) events.--  
SELECT 
    e1.id,
    e1.event,
    FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) AS utc_datetime,
    e1.voyage_From,
    e1.lat,
    e1.lon,
    e1.imo_num,
    e1.voyage_Id,
    e2.event AS next_event,
    FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400) AS next_utc_datetime,
    TIMESTAMPDIFF(SECOND, FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400), FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400)) AS duration_seconds
FROM 
    voyages e1
LEFT JOIN 
    voyages e2
ON 
    e1.voyage_Id = e2.voyage_Id 
    AND FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) < FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400)
WHERE 
    e1.imo_num = '9434761'
    AND e1.voyage_Id = '6'
    AND e1.allocatedVoyageId IS NULL
    AND e2.allocatedVoyageId IS NULL
    AND ((e1.event = 'SOSP' AND e2.event = 'EOSP') OR (e1.event = 'EOSP' AND e2.event = 'SOSP'))
ORDER BY 
    utc_datetime;

////////////////////////////////////////////////////////////////--
-- Calculate the cumulative sailing time and the time spent at ports for each voyage segment.
WITH voyage_events AS (
    SELECT 
        e1.id,
        e1.event,
        FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) AS utc_datetime,
        e1.voyage_Id,
        e2.event AS next_event,
        TIMESTAMPDIFF(SECOND, FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400), FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400)) AS duration_seconds
    FROM 
        voyages e1
    LEFT JOIN 
        voyages e2
    ON 
        e1.voyage_Id = e2.voyage_Id 
        AND FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) < FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400)
        AND e2.allocatedVoyageId IS NULL
    WHERE 
        e1.imo_num = '9434761'
        AND e1.voyage_Id = '6'
        AND e1.allocatedVoyageId IS NULL
)
SELECT 
    voyage_Id,
    SUM(CASE WHEN event = 'SOSP' AND next_event = 'EOSP' THEN duration_seconds ELSE 0 END) AS total_sailing_time_seconds,
    SUM(CASE WHEN event = 'EOSP' AND next_event = 'SOSP' THEN duration_seconds ELSE 0 END) AS total_port_stay_time_seconds
FROM 
    voyage_events
GROUP BY 
    voyage_Id;

///////////////////////////////////////////////////////--
-- Introduce geographic movement by calculating the distance between consecutive ports based on hypothetical latitude and longitude data.
WITH voyage_movements AS (
    SELECT 
        e1.id,
        e1.event,
        FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) AS utc_datetime,
        e1.voyage_From,
        e1.lat,
        e1.lon,
        e1.imo_num,
        e1.voyage_Id,
        e2.lat AS next_lat,
        e2.lon AS next_lon,
        e2.event AS next_event
    FROM 
        voyages e1
    LEFT JOIN 
        voyages e2
    ON 
        e1.voyage_Id = e2.voyage_Id 
        AND FROM_UNIXTIME((e1.dateStamp - 25569) * 86400 + e1.timeStamp * 86400) < FROM_UNIXTIME((e2.dateStamp - 25569) * 86400 + e2.timeStamp * 86400)
    WHERE 
        e1.imo_num = '9434761'
        AND e1.voyage_Id = '6'
        AND e1.allocatedVoyageId IS NULL
        AND e2.allocatedVoyageId IS NULL
)
SELECT 
    id,
    event,
    utc_datetime,
    voyage_From,
    lat,
    lon,
    imo_num,
    voyage_Id,
    next_lat,
    next_lon,
    next_event,
    CASE
        WHEN event = 'EOSP' AND next_event = 'SOSP' THEN 
            111.1 * SQRT(POW((next_lat - lat), 2) + POW((next_lon - lon), 2)) -- approximate distance in km
        ELSE NULL
    END AS distance_km
FROM 
    voyage_movements
WHERE 
    event = 'EOSP' AND next_event = 'SOSP';
