\COPY antennas FROM 'csv/antennas.csv' WITH CSV HEADER;
\COPY gamit_htc FROM 'csv/gamit_htc.csv' WITH CSV HEADER;
\COPY keys FROM 'csv/keys.csv' WITH CSV HEADER;
\COPY receivers FROM 'csv/receivers.csv' WITH CSV HEADER;
\COPY rinex_tank_struct FROM 'csv/rinex_tank_struct.csv' WITH CSV HEADER;

SELECT setval('public.antennas_api_id_seq', COALESCE((SELECT MAX(api_id) FROM antennas), 1), true);
SELECT setval('public.gamit_htc_api_id_seq', COALESCE((SELECT MAX(api_id) FROM gamit_htc), 1), true);
SELECT setval('public.keys_api_id_seq', COALESCE((SELECT MAX(api_id) FROM keys), 1), true);
SELECT setval('public.receivers_api_id_seq', COALESCE((SELECT MAX(api_id) FROM receivers), 1), true);
SELECT setval('public.rinex_tank_struct_api_id_seq', COALESCE((SELECT MAX(api_id) FROM rinex_tank_struct), 1), true);
