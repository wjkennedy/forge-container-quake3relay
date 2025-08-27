import {Text} from "@forge/react";
import React from 'react';

function InvokeServicePanelComponent( { data } ) {
    if (!data) {
        return (
            <>
                <Text>Loading...</Text>
            </>
        );
    } else {
        return (
            <>
                <Text>status: {data?.status}</Text>
                <Text>headers: {JSON.stringify(data?.headers, null, 2)}</Text>
                <Text>body.message: {data?.body?.message}</Text>
                <Text>body.appCurrentUser.accountType: {data?.body?.appCurrentUser?.accountType}</Text>
                <Text>body.userCurrentUser.accountType: {data?.body?.userCurrentUser?.accountType}</Text>
                <Text>body.requestDetails.headers: {JSON.stringify(data?.body?.requestDetails?.headers, null, 2)}</Text>
                <Text>body.requestDetails.body: {JSON.stringify(data?.body?.requestDetails?.body, null, 2)}</Text>
                <Text>body.requestDetails.queryParameters: {JSON.stringify(data?.body?.requestDetails?.queryParameters, null, 2)}</Text>
            </>
        );
    }
}

export default InvokeServicePanelComponent;

