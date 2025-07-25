import React, { useEffect, useState } from 'react';
import ForgeReconciler, { Text } from '@forge/react';
import { invokeService, __realtime } from '@forge/bridge';

const App = () => {
    const [data, setData] = useState(null);
    const [realtimeData, setRealtimeData] = useState(null);

    useEffect(() => {
        console.log("Calling POST /invoke-service ...")

        const fetchData = async () => {
            const data = await invokeService({
                method: 'POST',
                path: '/invoke-service?exampleStr=jira&exampleInt=123',
                body: JSON.stringify(
                    {
                        'message': 'Hello from jira issue panel'
                    }
                ),
                headers: {
                    'x-custom-request-header': 'x-custom-request-header-value'
                }
            });
            console.log(`POST /invoke-service response: ${JSON.stringify(data, null, 2)}`)
            setData(data);
        }

        fetchData()
    }, []);

    useEffect(() => {
        // This subscribes to a channel called "forge-container-realtime-channel", the "webtrigger-realtime" endpoint will publish to this channel.
        const subscribeToTopic = async () => {
            const onEvent = (payload) => {
                console.log('Received event with payload...: ', payload);
                setRealtimeData(payload);
            };
            const subscription = await __realtime.subscribe('forge-container-realtime-channel', onEvent);
            console.log('Subscribed to channel: forge-container-realtime-channel', subscription);
        }

          subscribeToTopic();
    }, []);

    if (!data) {
        return (
            <>
                <Text size="large">Data received from invokeService request</Text>
                <Text>Loading...</Text>
            </>
        );
    } else {
        return (
            <>
                <Text size="large">Realtime event received: {JSON.stringify(realtimeData, null, 2)}</Text>
                <Text size="large">Data received from invokeService request</Text>
                <Text>status: {data?.status}</Text>
                <Text>headers: {JSON.stringify(data?.headers, null, 2)}</Text>
                <Text>body.message: {data?.body?.message}</Text>
                <Text>body.requestDetails.headers: {JSON.stringify(data?.body?.requestDetails?.headers, null, 2)}</Text>
                <Text>body.requestDetails.body: {JSON.stringify(data?.body?.requestDetails?.body, null, 2)}</Text>
                <Text>body.requestDetails.queryParameters: {JSON.stringify(data?.body?.requestDetails?.queryParameters, null, 2)}</Text>
            </>
        );
    }

};

ForgeReconciler.render(
    <React.StrictMode>
        <App/>
    </React.StrictMode>
);
