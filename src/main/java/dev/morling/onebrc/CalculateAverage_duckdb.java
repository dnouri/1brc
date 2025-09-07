/*
 *  Copyright 2023 The original authors
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */
package dev.morling.onebrc;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

/**
 * DuckDB implementation that queries directly from CSV without intermediate storage.
 * This avoids the overhead of creating and populating a DuckDB table.
 */
public class CalculateAverage_duckdb {
    
    // Runtime configuration via system properties
    private static final int THREADS = Integer.parseInt(
        System.getProperty("duckdb.threads", String.valueOf(Runtime.getRuntime().availableProcessors()))
    );
    
    private static final String MEMORY_LIMIT = System.getProperty("duckdb.memory_limit", "4GB");
    private static final boolean PARALLEL_CSV = Boolean.parseBoolean(
        System.getProperty("duckdb.parallel_csv", "true")
    );

    private static final String FILE = "measurements.txt";
    
    public static void main(String[] args) throws Exception {
        // Load DuckDB driver
        Class.forName("org.duckdb.DuckDBDriver");
        
        // Configure and connect
        String url = String.format(
            "jdbc:duckdb:?threads=%d&memory_limit=%s",
            THREADS,
            MEMORY_LIMIT
        );
        
        try (Connection conn = DriverManager.getConnection(url);
             Statement stmt = conn.createStatement()) {
            
            // Single query: read CSV and aggregate directly
            String query = String.format("""
                SELECT 
                    station_name,
                    MIN(temperature) / 10.0 as min_temp,
                    CAST(AVG(temperature) AS DOUBLE) / 10.0 as mean_temp,
                    MAX(temperature) / 10.0 as max_temp
                FROM read_csv('%s',
                    delim = ';',
                    header = false,
                    columns = {
                        'station_name': 'VARCHAR',
                        'temperature': 'INTEGER'
                    },
                    parallel = %s
                )
                GROUP BY station_name
                ORDER BY station_name
                """, FILE, PARALLEL_CSV);
            
            // Execute and format results
            Map<String, String> results = new TreeMap<>();
            DecimalFormat fmt = new DecimalFormat("#0.0", DecimalFormatSymbols.getInstance(Locale.US));
            
            try (ResultSet rs = stmt.executeQuery(query)) {
                while (rs.next()) {
                    String station = rs.getString("station_name");
                    double min = rs.getDouble("min_temp");
                    double mean = rs.getDouble("mean_temp");
                    double max = rs.getDouble("max_temp");
                    
                    results.put(station, String.format("%s/%s/%s",
                        fmt.format(min),
                        fmt.format(mean),
                        fmt.format(max)
                    ));
                }
            }
            
            // Output results
            System.out.print("{");
            boolean first = true;
            for (Map.Entry<String, String> entry : results.entrySet()) {
                if (!first) System.out.print(", ");
                System.out.print(entry.getKey() + "=" + entry.getValue());
                first = false;
            }
            System.out.println("}");
        }
    }
}